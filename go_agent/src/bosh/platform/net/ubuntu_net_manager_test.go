package net_test

import (
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"

	boshlog "bosh/logger"
	. "bosh/platform/net"
	fakearp "bosh/platform/net/arp/fakes"
	fakenet "bosh/platform/net/fakes"
	boship "bosh/platform/net/ip"
	fakeip "bosh/platform/net/ip/fakes"
	boshsettings "bosh/settings"
	fakesys "bosh/system/fakes"
)

var _ = Describe("ubuntuNetManager", func() {
	var (
		fs                     *fakesys.FakeFileSystem
		cmdRunner              *fakesys.FakeCmdRunner
		defaultNetworkResolver *fakenet.FakeDefaultNetworkResolver
		ipResolver             *fakeip.FakeIPResolver
		addressBroadcaster     *fakearp.FakeAddressBroadcaster
		netManager             NetManager
	)

	BeforeEach(func() {
		fs = fakesys.NewFakeFileSystem()
		cmdRunner = fakesys.NewFakeCmdRunner()
		defaultNetworkResolver = &fakenet.FakeDefaultNetworkResolver{}
		ipResolver = &fakeip.FakeIPResolver{}
		addressBroadcaster = &fakearp.FakeAddressBroadcaster{}
		logger := boshlog.NewLogger(boshlog.LevelNone)
		netManager = NewUbuntuNetManager(
			fs,
			cmdRunner,
			defaultNetworkResolver,
			ipResolver,
			addressBroadcaster,
			logger,
		)
	})

	Describe("SetupDhcp", func() {
		const (
			dhcpConfPath  = "/etc/dhcp/dhclient.conf"
			dhcp3ConfPath = "/etc/dhcp3/dhclient.conf"

			expectedDHCPConfig = `# Generated by bosh-agent

option rfc3442-classless-static-routes code 121 = array of unsigned integer 8;

send host-name "<hostname>";

request subnet-mask, broadcast-address, time-offset, routers,
	domain-name, domain-name-servers, domain-search, host-name,
	netbios-name-servers, netbios-scope, interface-mtu,
	rfc3442-classless-static-routes, ntp-servers;

prepend domain-name-servers xx.xx.xx.xx, yy.yy.yy.yy, zz.zz.zz.zz;
`
		)

		var (
			networks boshsettings.Networks
		)

		BeforeEach(func() {
			networks = boshsettings.Networks{
				"bosh": boshsettings.Network{
					Default: []string{"dns"},
					DNS:     []string{"xx.xx.xx.xx", "yy.yy.yy.yy", "zz.zz.zz.zz"},
				},
				"vip": boshsettings.Network{
					Default: []string{},
					DNS:     []string{"aa.aa.aa.aa"},
				},
			}
		})

		ItRestartsDhcp := func() {
			Context("when ifconfig version is 0.7", func() {
				BeforeEach(func() {
					cmdRunner.AddCmdResult("ifup --version", fakesys.FakeCmdResult{
						Stdout: "ifup version 0.7.47",
					})
				})

				It("restarts dhclient", func() {
					err := netManager.SetupDhcp(networks, nil)
					Expect(err).ToNot(HaveOccurred())

					Expect(len(cmdRunner.RunCommands)).To(Equal(3))
					Expect(cmdRunner.RunCommands[1]).To(Equal([]string{"ifdown", "-a", "--no-loopback"}))
					Expect(cmdRunner.RunCommands[2]).To(Equal([]string{"ifup", "-a", "--no-loopback"}))
				})
			})

			Context("when ifconfig version is 0.6", func() {
				BeforeEach(func() {
					cmdRunner.AddCmdResult("ifup --version", fakesys.FakeCmdResult{
						Stdout: "ifup version 0.6.0",
					})
				})

				It("restarts dhclient", func() {
					err := netManager.SetupDhcp(networks, nil)
					Expect(err).ToNot(HaveOccurred())

					Expect(len(cmdRunner.RunCommands)).To(Equal(3))
					Expect(cmdRunner.RunCommands[1]).To(Equal([]string{"ifdown", "-a", "--exclude=lo"}))
					Expect(cmdRunner.RunCommands[2]).To(Equal([]string{"ifup", "-a", "--exclude=lo"}))
				})
			})
		}

		ItUpdatesDhcpConfig := func(dhcpConfPath string) {
			It("writes dhcp configuration", func() {
				err := netManager.SetupDhcp(networks, nil)
				Expect(err).ToNot(HaveOccurred())

				dhcpConfig := fs.GetFileTestStat(dhcpConfPath)
				Expect(dhcpConfig).ToNot(BeNil())
				Expect(dhcpConfig.StringContents()).To(Equal(expectedDHCPConfig))
			})

			It("writes out DNS servers in order that was provided by the network because *single* DHCP prepend command is used", func() {
				err := netManager.SetupDhcp(networks, nil)
				Expect(err).ToNot(HaveOccurred())

				dhcpConfig := fs.GetFileTestStat(dhcpConfPath)
				Expect(dhcpConfig).ToNot(BeNil())
				Expect(dhcpConfig.StringContents()).To(ContainSubstring(`
prepend domain-name-servers xx.xx.xx.xx, yy.yy.yy.yy, zz.zz.zz.zz;
`))
			})

			It("does not prepend any DNS servers if network does not provide them", func() {
				net := networks["bosh"]
				net.DNS = []string{}
				networks["bosh"] = net

				err := netManager.SetupDhcp(networks, nil)
				Expect(err).ToNot(HaveOccurred())

				dhcpConfig := fs.GetFileTestStat(dhcpConfPath)
				Expect(dhcpConfig).ToNot(BeNil())
				Expect(dhcpConfig.StringContents()).ToNot(ContainSubstring(`prepend domain-name-servers`))
			})
		}

		ItDoesNotRestartDhcp := func() {
			It("does not restart dhclient", func() {
				err := netManager.SetupDhcp(networks, nil)
				Expect(err).ToNot(HaveOccurred())

				Expect(len(cmdRunner.RunCommands)).To(Equal(0))
			})
		}

		ItBroadcastsMACAddresses := func() {
			It("starts broadcasting the MAC addresses", func() {
				errCh := make(chan error)

				err := netManager.SetupDhcp(networks, errCh)
				Expect(err).ToNot(HaveOccurred())

				<-errCh // wait for all arpings

				Expect(addressBroadcaster.BroadcastMACAddressesAddresses).To(Equal([]boship.InterfaceAddress{
					boship.NewResolvingInterfaceAddress("eth0", ipResolver),
				}))
			})
		}

		Context("when dhclient3 is installed on the system", func() {
			BeforeEach(func() { cmdRunner.CommandExistsValue = true })

			Context("when dhcp was not previously configured", func() {
				ItUpdatesDhcpConfig(dhcp3ConfPath)
				ItRestartsDhcp()
				ItBroadcastsMACAddresses()
			})

			Context("when dhcp was previously configured with different configuration", func() {
				BeforeEach(func() {
					fs.WriteFileString(dhcp3ConfPath, "fake-other-configuration")
				})

				ItUpdatesDhcpConfig(dhcp3ConfPath)
				ItRestartsDhcp()
				ItBroadcastsMACAddresses()
			})

			Context("when dhcp was previously configured with the same configuration", func() {
				BeforeEach(func() {
					fs.WriteFileString(dhcp3ConfPath, expectedDHCPConfig)
				})

				ItUpdatesDhcpConfig(dhcp3ConfPath)
				ItDoesNotRestartDhcp()
				ItBroadcastsMACAddresses()
			})
		})

		Context("when dhclient3 is not installed on the system", func() {
			BeforeEach(func() { cmdRunner.CommandExistsValue = false })

			Context("when dhcp was not previously configured", func() {
				ItUpdatesDhcpConfig(dhcpConfPath)
				ItRestartsDhcp()
			})

			Context("when dhcp was previously configured with different configuration", func() {
				BeforeEach(func() {
					fs.WriteFileString(dhcpConfPath, "fake-other-configuration")
				})

				ItUpdatesDhcpConfig(dhcpConfPath)
				ItRestartsDhcp()
			})

			Context("when dhcp was previously configured with the same configuration", func() {
				BeforeEach(func() {
					fs.WriteFileString(dhcpConfPath, expectedDHCPConfig)
				})

				ItUpdatesDhcpConfig(dhcpConfPath)
				ItDoesNotRestartDhcp()
			})
		})
	})

	Describe("SetupManualNetworking", func() {
		const (
			expectedNetworkInterfaces = `# Generated by bosh-agent
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.195.6
    network 192.168.195.0
    netmask 255.255.255.0
    broadcast 192.168.195.255
    gateway 192.168.195.1`

			expectedResolvConf = `# Generated by bosh-agent
nameserver 10.80.130.2
nameserver 10.80.130.1
`
		)

		var (
			errCh chan error
		)

		BeforeEach(func() {
			errCh = make(chan error)
		})

		BeforeEach(func() {
			// For mac addr to interface resolution
			fs.WriteFile("/sys/class/net/eth0", []byte{})
			fs.WriteFileString("/sys/class/net/eth0/address", "22:00:0a:1f:ac:2a\n")
			fs.SetGlob("/sys/class/net/*", []string{"/sys/class/net/eth0"})
		})

		networks := boshsettings.Networks{
			"bosh": boshsettings.Network{
				Default: []string{"dns", "gateway"},
				IP:      "192.168.195.6",
				Netmask: "255.255.255.0",
				Gateway: "192.168.195.1",
				Mac:     "22:00:0a:1f:ac:2a",
				DNS:     []string{"10.80.130.2", "10.80.130.1"},
			},
		}

		Context("when manual networking was not previously configured", func() {
			It("writes /etc/network/interfaces", func() {
				err := netManager.SetupManualNetworking(networks, nil)
				Expect(err).ToNot(HaveOccurred())

				networkConfig := fs.GetFileTestStat("/etc/network/interfaces")
				Expect(networkConfig).ToNot(BeNil())
				Expect(networkConfig.StringContents()).To(Equal(expectedNetworkInterfaces))
			})

			It("restarts networking", func() {
				err := netManager.SetupManualNetworking(networks, errCh)
				Expect(err).ToNot(HaveOccurred())

				<-errCh // wait for all arpings

				Expect(len(cmdRunner.RunCommands) >= 2).To(BeTrue())
				Expect(cmdRunner.RunCommands[0]).To(Equal([]string{"service", "network-interface", "stop", "INTERFACE=eth0"}))
				Expect(cmdRunner.RunCommands[1]).To(Equal([]string{"service", "network-interface", "start", "INTERFACE=eth0"}))
			})

			It("updates /etc/resolv.conf", func() {
				err := netManager.SetupManualNetworking(networks, nil)
				Expect(err).ToNot(HaveOccurred())

				resolvConf := fs.GetFileTestStat("/etc/resolv.conf")
				Expect(resolvConf).ToNot(BeNil())
				Expect(resolvConf.StringContents()).To(Equal(expectedResolvConf))
			})

			It("writes out DNS servers in order that was provided by the network", func() {
				err := netManager.SetupManualNetworking(networks, nil)
				Expect(err).ToNot(HaveOccurred())

				resolvConf := fs.GetFileTestStat("/etc/resolv.conf")
				Expect(resolvConf).ToNot(BeNil())
				Expect(resolvConf.StringContents()).To(ContainSubstring(`
nameserver 10.80.130.2
nameserver 10.80.130.1
`))
			})

			It("starts broadcasting the MAC addresses", func() {
				err := netManager.SetupManualNetworking(networks, errCh)
				Expect(err).ToNot(HaveOccurred())

				<-errCh // wait for all arpings

				Expect(addressBroadcaster.BroadcastMACAddressesAddresses).To(Equal([]boship.InterfaceAddress{
					boship.NewSimpleInterfaceAddress("eth0", "192.168.195.6"),
				}))
			})
		})

		Context("when manual networking was previously configured with different configuration", func() {
			BeforeEach(func() {
				fs.WriteFileString("/etc/network/interfaces", "fake-manual-config")
			})

			It("updates /etc/network/interfaces", func() {
				err := netManager.SetupManualNetworking(networks, nil)
				Expect(err).ToNot(HaveOccurred())

				networkConfig := fs.GetFileTestStat("/etc/network/interfaces")
				Expect(networkConfig).ToNot(BeNil())
				Expect(networkConfig.StringContents()).To(Equal(expectedNetworkInterfaces))
			})

			It("restarts networking", func() {
				err := netManager.SetupManualNetworking(networks, errCh)
				Expect(err).ToNot(HaveOccurred())

				<-errCh // wait for all arpings

				Expect(len(cmdRunner.RunCommands) >= 2).To(BeTrue())
				Expect(cmdRunner.RunCommands[0]).To(Equal([]string{"service", "network-interface", "stop", "INTERFACE=eth0"}))
				Expect(cmdRunner.RunCommands[1]).To(Equal([]string{"service", "network-interface", "start", "INTERFACE=eth0"}))
			})

			It("updates dns", func() {
				err := netManager.SetupManualNetworking(networks, nil)
				Expect(err).ToNot(HaveOccurred())

				resolvConf := fs.GetFileTestStat("/etc/resolv.conf")
				Expect(resolvConf).ToNot(BeNil())
				Expect(resolvConf.StringContents()).To(Equal(expectedResolvConf))
			})

			It("starts broadcasting the MAC addresses", func() {
				err := netManager.SetupManualNetworking(networks, errCh)
				Expect(err).ToNot(HaveOccurred())

				<-errCh // wait for all arpings

				Expect(addressBroadcaster.BroadcastMACAddressesAddresses).To(Equal([]boship.InterfaceAddress{
					boship.NewSimpleInterfaceAddress("eth0", "192.168.195.6"),
				}))
			})
		})

		Context("when manual networking was previously configured with same configuration", func() {
			BeforeEach(func() {
				fs.WriteFileString("/etc/network/interfaces", expectedNetworkInterfaces)
			})

			It("keeps same /etc/network/interfaces", func() {
				err := netManager.SetupManualNetworking(networks, nil)
				Expect(err).ToNot(HaveOccurred())

				networkConfig := fs.GetFileTestStat("/etc/network/interfaces")
				Expect(networkConfig).ToNot(BeNil())
				Expect(networkConfig.StringContents()).To(Equal(expectedNetworkInterfaces))
			})

			It("does not restart networking because configuration did not change", func() {
				err := netManager.SetupManualNetworking(networks, errCh)
				Expect(err).ToNot(HaveOccurred())

				<-errCh // wait for all arpings

				for _, cmd := range cmdRunner.RunCommands {
					Expect(cmd[0]).ToNot(Equal("service"))
				}
			})

			It("updates /etc/resolv.conf for DNS", func() {
				err := netManager.SetupManualNetworking(networks, nil)
				Expect(err).ToNot(HaveOccurred())

				resolvConf := fs.GetFileTestStat("/etc/resolv.conf")
				Expect(resolvConf).ToNot(BeNil())
				Expect(resolvConf.StringContents()).To(Equal(expectedResolvConf))
			})

			It("starts broadcasting the MAC addresses", func() {
				err := netManager.SetupManualNetworking(networks, errCh)
				Expect(err).ToNot(HaveOccurred())

				<-errCh // wait for all arpings

				Expect(addressBroadcaster.BroadcastMACAddressesAddresses).To(Equal([]boship.InterfaceAddress{
					boship.NewSimpleInterfaceAddress("eth0", "192.168.195.6"),
				}))
			})
		})
	})
})