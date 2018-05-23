"""
Linux on Hyper-V and Azure Test Code, ver. 1.0.0
Copyright (c) Microsoft Corporation

All rights reserved
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

See the Apache Version 2.0 License for specific language governing
permissions and limitations under the License.
"""

from __future__ import print_function
import os
import re
import logging
import sql_utils
from copy import deepcopy
from file_parser import ParseXML, parse_ica_log, FIOLogsReader, FIOLogsReaderRaid,\
    NTTTCPLogsReader, IPERFLogsReader, LatencyLogsReader
from virtual_machine import VirtualMachine


logger = logging.getLogger(__name__)


class TestRun(object):
    """Main class that encapsulates the information necessary for the parsing process

    TestRun class is being used to store test run specific data and launch
    different parsing methods in order to process the output of a test run.
    """
    def __init__(self, skip_vm_check=False, checkpoint_name=False):
        self.suite = ''
        self.timestamp = ''
        self.log_path = ''
        self.vms = dict()
        self.validate_vm = not skip_vm_check
        self.test_cases = dict()
        self.server_name = os.environ['COMPUTERNAME']
        self.checkpoint_name = checkpoint_name
        self.guest_os = ''
        self.guest_distro = ''
        self.kernel_version = ''

    def update_from_xml(self, xml_path):
        xml_object = ParseXML(xml_path)
        logger.debug('Parsed XML file')
        self.suite = xml_object.get_tests_suite()
        logger.debug('Saving Tests Suite name - %s', self.suite)

        for test_case_name, props in xml_object.get_tests().iteritems():
            logger.debug('Initializing TestCase object for %s', test_case_name)
            self.test_cases[test_case_name] = TestCase(
                name=test_case_name,
                properties=props
            )

        for vm_name, vm_details in xml_object.get_vms().iteritems():
            logger.debug('Initializing VirtualMachine object for %s', vm_name)
            self.vms[vm_name] = VirtualMachine(
                vm_name=vm_name,
                hv_server=vm_details['hvServer'],
                os=vm_details['os'],
                check=self.validate_vm,
                checkpoint_name=self.checkpoint_name
                )

    def update_from_ica(self, log_path):
        parsed_ica = parse_ica_log(log_path)
        logger.debug('Parsed ICA log file')
        logger.debug('Parsed content %s', parsed_ica)

        self.timestamp = parsed_ica['timestamp']
        logger.debug('Saving timestamp - %s', self.timestamp)

        try:
            self.log_path = parsed_ica['logPath']
            self.guest_os = 'FreeBSD'
            self.guest_distro = parsed_ica['GuestDistro']
            self.kernel_version = parsed_ica['KernelVersion']
            logger.debug('Saving log folder path - %s', self.log_path)
        except KeyError:
            logger.warning('Log folder path not found in ICA log')

        for vm_name, props in parsed_ica['vms'].iteritems():
            logger.debug('Updating VM, %s, with details from ICA log',
                         vm_name)
            self.vms[vm_name].host_os = props['hostOS']
            self.vms[vm_name].hv_server = props['hvServer']
            self.vms[vm_name].location = props['TestLocation']

        to_remove = []
        remove_vms = self.vms.keys()
        for test_name, test_props in self.test_cases.iteritems():
            try:
                self.test_cases[test_name].update_results(parsed_ica['tests'][test_name])

                # Remove dependency VMs
                if parsed_ica['tests'][test_name][0] in remove_vms:
                    remove_vms.remove(parsed_ica['tests'][test_name][0])

                logger.debug(
                    'Saving test result for %s - %s',
                    test_name, parsed_ica['tests'][test_name][1]
                )
            except KeyError:
                logger.warning('Result for %s was not found in ICA log file', test_name)
                to_remove.append(test_name)

        if remove_vms:
            for vm_name in remove_vms:
                del self.vms[vm_name]

        if to_remove:
            self.remove_cases(to_remove)

    def remove_cases(self, test_names_list):
        for test_case in test_names_list:
            del self.test_cases[test_case]

    def update_from_vm(self, kvp_fields, stop_vm=True):
        if not self.validate_vm:
            stop_vm = False

        for vm_name, vm_object in self.vms.iteritems():
            vm_object.update_from_kvp(kvp_fields, stop_vm)

    def parse_for_db_insertion(self):
        insertion_list = list()
        for test_name, test_object in self.test_cases.iteritems():
            for vm_name, vm_object in self.vms.iteritems():
                test_dict = dict()
                try:
                    test_dict['TestResult'] = test_object.results[vm_name]
                except KeyError:
                    logger.error('Unable to find test result for %s on vm %s',
                                 test_name, vm_name)
                    logger.info('Skipping %s for database insertion', test_name)
                    continue

                test_dict['HostName'] = vm_object.hv_server
                test_dict['HostVersion'] = vm_object.host_os
                test_dict['TestCaseName'] = test_name
                test_dict['TestArea'] = self.suite
                test_dict['TestDate'] = TestRun.format_date(
                    self.timestamp
                )

                if not vm_object.kvp_info:
                    test_dict['GuestOS'] = ''
                    test_dict['KernelVersion'] = ''
                    logger.warning('No values found for VM Distro and '
                                   'VM Kernel Version')
                else:
                    try:
                        """For some distros OSMajorVersion field is empty"""
                        # Apparently in some cases OSMajorVersion is saved as none
                        # TODO : Refactor this quick fix
                        if not vm_object.kvp_info['OSMajorVersion']:
                            test_dict['GuestOS'] = vm_object.kvp_info[
                                'OSName']
                        else:
                            test_dict['GuestOS'] = ' '.join([
                                vm_object.kvp_info['OSName'],
                                vm_object.kvp_info['OSMajorVersion']
                            ])
                    except KeyError:
                        test_dict['GuestOS'] = vm_object.kvp_info['OSName']
                    test_dict['KernelVersion'] = vm_object.kvp_info['OSBuildNumber']

                test_dict['GuestOS'] = self.guest_os
                test_dict['KernelVersion'] = self.kernel_version
                test_dict['GuestDistro'] = self.guest_distro
                logger.debug('Parsed line %s for insertion', test_dict)
                insertion_list.append(test_dict)

        return insertion_list

    @staticmethod
    def format_date(test_date):
        """Formats the date taken from the log file

             in order to align with the sql date format - YMD
            """

        split_date = test_date.split()
        split_date[0] = split_date[0].split('/')
        return ''.join(
            [split_date[0][2], split_date[0][0], split_date[0][1]]
        )


class PerfTestRun(TestRun):
    def __init__(self, perf_path, skip_vm_check=True, checkpoint_name=False, db_cursor=None):
        super(PerfTestRun, self).__init__(skip_vm_check, checkpoint_name)
        self.perf_path = perf_path
        self.db_cursor = db_cursor

    def update_from_ica(self, log_path):
        super(PerfTestRun, self).update_from_ica(log_path)
        parsed_perf_log = None
        if self.suite.lower() == 'fio-singledisk':
            parsed_perf_log = FIOLogsReader(self.perf_path).process_logs()
        if self.suite.lower() == 'fio-raid0-4disks':
            parsed_perf_log = FIOLogsReaderRaid(self.perf_path).process_logs()
        elif self.suite.lower() in ['ntttcp', 'tcp']:
            parsed_perf_log = NTTTCPLogsReader(self.perf_path).process_logs()
        elif self.suite.lower() in ['iperf', 'udp']:
            parsed_perf_log = IPERFLogsReader(self.perf_path).process_logs()
        elif self.suite.lower() in ['latency']:
            parsed_perf_log = LatencyLogsReader(self.perf_path).process_logs()

        tests_cases = dict()
        test_index = 0
        for perf_test in parsed_perf_log:
            test_case = deepcopy(self.test_cases)
            test_case.values()[0].perf_dict = perf_test
            test_index += 1
            tests_cases.update({
                test_case.keys()[0] + str(test_index): test_case.values()[0]
            })

        self.test_cases = tests_cases

    def parse_for_db_insertion(self):
        insertion_list = super(PerfTestRun, self).parse_for_db_insertion()

        for table_dict in insertion_list:
            del table_dict['TestResult']
            del table_dict['TestArea']
            del table_dict['HostName']
            
            table_dict['GuestOS'] = table_dict.pop('GuestOSDistro')
            table_dict['GuestDistro'] = table_dict.pop('GuestOSDistro')
            table_dict['HostBy'] = os.environ['COMPUTERNAME']
            table_dict['HostOS'] = table_dict.pop('HostVersion')
            table_dict['HostType'] = table_dict.pop('TestLocation')

            # TODO - Find fix for hardcoded values
            table_dict['GuestSize'] = '8VP8G40G'

            test_case_obj = self.test_cases[table_dict['TestCaseName']]
            if self.suite.lower() in ['fio-singledisk', 'fio-raid0-4disks']:
                self.prep_for_fio(table_dict, test_case_obj)
            elif self.suite.lower() in ['ntttcp', 'tcp']:
                self.prep_for_ntttcp(table_dict, test_case_obj)
            elif self.suite.lower() in ['iperf', 'udp']:
                self.prep_for_iperf(table_dict, test_case_obj)
            elif self.suite.lower() in ['latency']:
                self.prep_for_latency(table_dict, test_case_obj)

            if 'fio' not in self.suite.lower():
                if 'sriov' in table_dict['TestCaseName'].lower():
                    table_dict['DataPath'] = 'SRIOV'
                else:
                    table_dict['DataPath'] = 'Synthetic'

            table_dict['TestCaseName'] = re.match('(.*[a-z]+)[0-9]*',
                                                  table_dict['TestCaseName']).group(1)

        if self.suite.lower() in ['fio-singledisk', 'fio-raid0-4disks']:
            insertion_list = sorted(insertion_list, key=lambda column: (
                column['QDepth'], column['BlockSize_KB']))
        elif self.suite.lower() == 'ntttcp':
            insertion_list = sorted(insertion_list, key=lambda column: (
                column['ProtocolType'], column['NumberOfConnections']))
        elif self.suite.lower() == 'iperf':
            insertion_list = sorted(insertion_list, key=lambda column: (
                column['NumberOfConnections'], column['SendBufSize_KBytes']))
        print(insertion_list)
        return insertion_list

    @staticmethod
    def prep_for_fio(table_dict, test_case_obj):
        table_dict['rand_read_iops'] = float(test_case_obj.perf_dict['rand-read:'])
        table_dict['rand_read_lat_usec'] = test_case_obj.perf_dict['rand-read: latency']
        table_dict['rand_write_iops'] = float(test_case_obj.perf_dict['rand-write:'])
        table_dict['rand_write_lat_usec'] = float(test_case_obj.perf_dict['rand-write: latency'])
        table_dict['seq_read_iops'] = float(test_case_obj.perf_dict['seq-read:'])
        table_dict['seq_write_iops'] = float(test_case_obj.perf_dict['seq-write:'])
        table_dict['seq_write_lat_usec'] = float(test_case_obj.perf_dict['seq-write: latency'])
        table_dict['seq_read_lat_usec'] = float(test_case_obj.perf_dict['seq-read: latency'])
        table_dict['QDepth'] = test_case_obj.perf_dict['QDepth']
        table_dict['BlockSize_KB'] = test_case_obj.perf_dict['BlockSize_KB']

    @staticmethod
    def prep_for_ntttcp(table_dict, test_case_obj):
        table_dict['NumberOfConnections'] = int(test_case_obj.perf_dict['NumberOfConnections'])
        table_dict['Throughput_Gbps'] = float(test_case_obj.perf_dict['Throughput_Gbps'])
        table_dict['Latency_ms'] = float(test_case_obj.perf_dict['AverageLatency_ms'])
        table_dict['PacketSize_KBytes'] = float(test_case_obj.perf_dict['PacketSize_KBytes'])
        table_dict['SenderCyclesPerByte'] = float(test_case_obj.perf_dict['SenderCyclesPerByte'])
        table_dict['ReceiverCyclesPerByte'] = float(test_case_obj.perf_dict[
                                                        'ReceiverCyclesPerByte'])
        table_dict['IPVersion'] = test_case_obj.perf_dict['IPVersion']
        table_dict['ProtocolType'] = test_case_obj.perf_dict['Protocol']

    @staticmethod
    def prep_for_iperf(table_dict, test_case_obj):
        table_dict['NumberOfConnections'] = int(test_case_obj.perf_dict['NumberOfConnections'])
        table_dict['TxThroughput_Gbps'] = float(test_case_obj.perf_dict['TxThroughput_Gbps'])
        table_dict['RxThroughput_Gbps'] = float(test_case_obj.perf_dict['RxThroughput_Gbps'])
        table_dict['DatagramLoss'] = float(test_case_obj.perf_dict['DatagramLoss'])
        table_dict['PacketSize_KBytes'] = float(test_case_obj.perf_dict['PacketSize_KBytes'])
        table_dict['IPVersion'] = test_case_obj.perf_dict['IPVersion']
        table_dict['ProtocolType'] = test_case_obj.perf_dict['Protocol']
        table_dict['SendBufSize_KBytes'] = test_case_obj.perf_dict['SendBufSize_KBytes']

    @staticmethod
    def prep_for_latency(table_dict, test_case_obj):
        table_dict['IPVersion'] = test_case_obj.perf_dict['IPVersion']
        table_dict['ProtocolType'] = test_case_obj.perf_dict['ProtocolType']
        table_dict['MinLatency_us'] = float(test_case_obj.perf_dict['MinLatency_us'])
        table_dict['AverageLatency_us'] = float(test_case_obj.perf_dict['AverageLatency_us'])
        table_dict['MaxLatency_us'] = float(test_case_obj.perf_dict['MaxLatency_us'])
        table_dict['Latency95Percentile_us'] = float(test_case_obj.perf_dict[
                                                         'Latency95Percentile_us'])
        table_dict['Latency99Percentile_us'] = float(test_case_obj.perf_dict[
                                                         'Latency99Percentile_us'])


class TestCase(object):
    def __init__(self, name, properties):
        self.name = name
        self.covered_cases = self.get_covered_cases(properties)
        self.results = dict()
        self.perf_dict = dict()

    def update_results(self, vm_result):
        self.results[vm_result[0]] = vm_result[1]

    def get_covered_cases(self, properties):
        try:
            for param_name, value in properties['testparams']:
                if param_name == 'TC_COVERED':
                    return value
        except KeyError:
            logger.warning('No test case ID found for %s', self.name)

        return 'NO_ID'
