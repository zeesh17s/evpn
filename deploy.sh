
sudo modprobe mpls_router
sudo modprobe mpls_iptunnel
sudo sh -c "echo 1 > /proc/sys/net/mpls/conf/eth0/input"

# Mpls-core subnet
docker network create --driver=bridge --subnet=2.2.0.0/16 PE1_LSR1
docker network create --driver=bridge --subnet=3.3.0.0/16 PE1_LSR2
docker network create --driver=bridge --subnet=4.4.0.0/16 LSR1_PE2
docker network create --driver=bridge --subnet=5.5.0.0/16 LSR2_PE2

# Customer subnets
docker network create --driver=bridge --subnet=12.12.0.0/16 CustX_PE1
docker network create --driver=bridge --subnet=13.13.1.0/25 CustZ_PE1
docker network create --driver=bridge --subnet=14.14.0.0/16 PE2_CustX
docker network create --driver=bridge --subnet=13.13.1.128/25 PE2_CustZ


create_router() {

 [ ! -d $(pwd)/configs/$4 ] && { mkdir -p $(pwd)/configs/$4; touch $(pwd)/configs/$4/daemons;  }

docker create --name $1 -h $1 --network $2 --ip $3 --sysctl net.mpls.conf.lo.input=1 --sysctl net.mpls.conf.eth0.input=1 \
--sysctl net.mpls.platform_labels=1000 --cap-add=NET_ADMIN --cap-add SYS_ADMIN  -it -v $(pwd)/configs/$4:/etc/frr  \
 --privileged  quay.io/frrouting/frr:9.0.1 bash
}

# Create Core Routers with ip addresses assigned on interface eth0
create_router PE-1  PE1_LSR1 2.2.0.10 pe1
create_router LSR-1 PE1_LSR1 2.2.0.11 lsr1
create_router PE-2  LSR1_PE2 4.4.0.10 pe2
create_router LSR-2 PE1_LSR2 3.3.0.11 lsr2

docker start PE-1
docker start LSR-1
docker start LSR-2
docker start PE-2


# assigning ip addresses on interface eth1
docker network connect PE1_LSR2 --ip 3.3.0.10 PE-1
docker network connect LSR1_PE2 --ip 4.4.0.11 LSR-1
docker network connect LSR2_PE2 --ip 5.5.0.11 LSR-2
docker network connect LSR2_PE2 --ip 5.5.0.10 PE-2


# mpls config
find /proc/sys/net/mpls/conf/* -type f -regex ".*\(br\|veth\).*" | xargs -I{} sudo sh -c 'printf 1 >  $1' -- {}
sudo bash -c "echo 1000 > /proc/sys/net/mpls/platform_labels"

# requires docker cotianer to be run in privileged mode.
update_eth1_input() {
 docker exec -d $1 sh -c "echo 1 > /proc/sys/net/mpls/conf/eth1/input"
}

update_eth1_input PE-1
update_eth1_input LSR-1
update_eth1_input LSR-2
update_eth1_input PE-2

echo "Runing daemons on LSR routers"
docker exec -d PE-1 sh -c "/usr/lib/frr/watchfrr zebra ospfd ldpd bgpd ripd"
docker exec -d LSR-1 /usr/lib/frr/watchfrr zebra ospfd ldpd
docker exec -d LSR-2 /usr/lib/frr/watchfrr zebra ospfd ldpd
docker exec -d PE-2 /usr/lib/frr/watchfrr zebra ospfd ldpd bgpd ripd

echo "Assigning loopbacks to core routers"
lo_pe1=33.33.33.33
lo_lsr1=22.22.22.22
lo_lsr2=55.55.55.55
lo_pe2=44.44.44.44
docker exec -d PE-1  ip address add $lo_pe1 dev lo
docker exec -d LSR-1 ip address add $lo_lsr1 dev lo
docker exec -d LSR-2 ip address add $lo_lsr2 dev lo
docker exec -d PE-2  ip address add $lo_pe2 dev lo


echo "Waiting for the daemons to initialize..."
sleep 5

# osfp
echo "Configuring ospf protocol..."
docker exec -d PE-1 vtysh -c "configure" \
               -c "router ospf" \
               -c "network 2.2.0.0/16 area 0" \
               -c "network 3.3.0.0/16 area 0" \
               -c "network $lo_pe1/32 area 0" \
               -c "exit";

docker exec -d PE-2 vtysh -c "configure" \
               -c "router ospf" \
               -c "network 4.4.0.0/16 area 0" \
               -c "network 5.5.0.0/16 area 0" \
               -c "network $lo_pe2/32 area 0" \
               -c "exit"

docker exec -d LSR-1 vtysh -c "configure" \
               -c "router ospf" \
               -c "network 2.2.0.0/16 area 0" \
               -c "network 4.4.0.0/16 area 0" \
               -c "network $lo_lsr1/32 area 0" \
               -c "exit";

docker exec -d LSR-2 vtysh -c "configure" \
               -c "router ospf" \
               -c "network 3.3.0.0/16 area 0" \
               -c "network 5.5.0.0/16 area 0" \
               -c "network $lo_lsr2/32 area 0" \
               -c "exit";

# Mpls ldp
echo "Configuring Mpls ldp protocol"..
docker exec -d PE-1 vtysh -c "configure" \
               -c "mpls ldp" \
               -c "router-id $lo_pe1" \
               -c "neighbor $lo_lsr1 password ldp_mpls" \
               -c "neighbor $lo_lsr2 password ldp_mpls" \
               -c "address-family ipv4" \
               -c "discovery transport-address $lo_pe1" \
               -c "interface eth0" \
               -c "exit" \
               -c "interface eth1" \
               -c "end";

docker exec -d LSR-1 vtysh -c "configure" \
               -c "mpls ldp" \
               -c "router-id $lo_lsr1" \
               -c "neighbor $lo_pe1 password ldp_mpls" \
               -c "neighbor $lo_pe2 password ldp_mpls" \
               -c "address-family ipv4" \
               -c "discovery transport-address $lo_lsr1" \
               -c "interface eth0" \
               -c "exit" \
               -c "interface eth1" \
               -c "end";

docker exec -d LSR-2 vtysh -c "configure" \
               -c "mpls ldp" \
               -c "router-id $lo_lsr2" \
               -c "neighbor $lo_pe1 password ldp_mpls" \
               -c "neighbor $lo_pe2 password ldp_mpls" \
               -c "address-family ipv4" \
               -c "discovery transport-address $lo_lsr2" \
               -c "interface eth0" \
               -c "exit" \
               -c "interface eth1" \
               -c "end";
docker exec -d PE-2 vtysh -c "configure" \
               -c "mpls ldp" \
               -c "router-id $lo_pe2" \
               -c "neighbor $lo_lsr1 password ldp_mpls" \
               -c "neighbor $lo_lsr2 password ldp_mpls" \
               -c "address-family ipv4" \
               -c "discovery transport-address $lo_pe2" \
               -c "interface eth0" \
               -c "exit" \
               -c "interface eth1" \
               -c "end";


# initializing customer facing interfaces
docker network connect CustX_PE1 --ip 12.12.0.5 PE-1   #eth2
docker network connect CustZ_PE1 --ip 13.13.1.8 PE-1   #eth3
docker network connect PE2_CustX --ip 14.14.0.5 PE-2   #eth2
docker network connect PE2_CustZ --ip 13.13.1.132 PE-2  #eth3


#VRF interface
# cust x
docker exec -d PE-1 sh -c "ip link add custx type vrf table 22  && \
                           ip link set dev custx up  && \
                           ip link set dev eth2 master custx  && \
                           ip route add table 22 unreachable default metric 4278198272 "
docker exec -d PE-2 sh -c "ip link add custx_b type vrf table 42  && \
                           ip link set dev custx_b up  && \
                           ip link set dev eth2 master custx_b  && \
                           ip route add table 42 unreachable default metric 4278198272 "


# MP-BGP
echo "Configuring MP-BGP"
# Establish peering
docker exec -d PE-1 vtysh -c "configure" \
                        -c "router bgp 64502" \
                        -c "neighbor $lo_pe2 remote-as 64502" \
                        -c "neighbor $lo_pe2 update-source lo" \
                        -c "address-family ipv4 unicast" \
                        -c "no neighbor $lo_pe2 activate" \
                        -c "network 10.0.10.1/24" \
                        -c "exit-address-family" \
                        -c "address-family ipv4 vpn" \
                        -c "neighbor $lo_pe2 activate" \
                        -c "exit-address-family" \
                        -c "exit"

 docker exec -d PE-2 vtysh -c "configure" \
                        -c "router bgp 64502" \
                        -c "neighbor $lo_pe1 remote-as 64502" \
                        -c "neighbor $lo_pe1 update-source lo" \
                        -c "address-family ipv4 unicast" \
                        -c "no neighbor $lo_pe1 activate" \
                        -c "network 10.1.10.1/24" \
                        -c "exit-address-family" \
                        -c "address-family ipv4 vpn" \
                        -c "neighbor $lo_pe1 activate" \
                        -c "exit-address-family" \
                        -c "exit"              
# Establish VPNv4 
 docker exec -d PE-1 vtysh -c "configure" \
                        -c "router bgp 64502 vrf custx" \
                        -c "address-family ipv4 unicast" \
                        -c "redistribute rip" \
                        -c "label vpn export auto" \
                        -c "rd vpn export 64052:12" \
                        -c "rt vpn both 64502:89" \
                        -c "export vpn" \
                        -c "import vpn" \
                        -c "exit-address-family" \
                        -c "exit"

 docker exec -d PE-2 vtysh -c "configure" \
                        -c "router bgp 64502 vrf custx_b" \
                        -c "address-family ipv4 unicast" \
                        -c "redistribute rip" \
                        -c "label vpn export auto" \
                        -c "rd vpn export 64052:14" \
                        -c "rt vpn both 64502:89" \
                        -c "export vpn" \
                        -c "import vpn" \
                        -c "exit-address-family" \
                        -c "exit"


# cust X 
docker run -itd --name cust_x_a -h cust_x_a --network CustX_PE1 --ip 12.12.0.9 \
    --cap-add=NET_ADMIN --cap-add SYS_ADMIN  quay.io/frrouting/frr:9.0.1 sh -c "/usr/lib/frr/watchfrr zebra ripd"
docker run -itd --name cust_x_b -h cust_x_b --network PE2_CustX --ip 14.14.0.11  \
    --cap-add=NET_ADMIN --cap-add SYS_ADMIN quay.io/frrouting/frr:9.0.1 sh -c "/usr/lib/frr/watchfrr zebra ripd"

docker exec cust_x_a sh -c "ip address add 192.168.1.7/32 dev lo"
docker exec cust_x_b sh -c "ip address add 173.26.2.9/32 dev lo"

sleep 5

docker exec -d PE-1 vtysh -c "configure" \
               -c "router rip vrf custx" \
               -c "network 12.12.0.0/16" \
               -c "redistribute bgp" \
               -c "exit"
docker exec -d PE-2 vtysh -c "configure" \
               -c "router rip vrf custx_b" \
               -c "network 14.14.0.0/16" \
               -c "redistribute bgp" \
               -c "exit" 


docker exec -d cust_x_a vtysh -c "configure" \
                               -c "router rip" \
                               -c "network 192.168.1.7/24" \
                               -c "network eth0" \
                               -c "exit"
docker exec -d cust_x_b vtysh -c "configure" \
                               -c "router rip" \
                               -c "network 173.26.2.9/24" \
                               -c "network eth0" \
                               -c "exit" 


# Cust Z
# VRF interface config  
# L2VNI 
docker exec -d PE-1 sh -c "ip link add custz type vrf table 32  && \
                           ip link set dev custz up  && \                   
                           ip route add table 32 unreachable default metric 4278198272  && \                          
                           ip link add br100 type bridge && \
                           ip link set br100 master custz && \                                                 
                           ip addr add 13.13.1.8/24 dev br100 && \
                           ip addr delete 13.13.1.8/25 dev eth3 && \
                           ip link add vni100 type vxlan local $lo_pe1 dstport 4789 id 100 nolearning && \
                           ip link set vni100 master br100 addrgenmode none && \
                           ip link set vni100 type bridge_slave neigh_suppress on learning off && \
                           ip link set dev eth3 master br100 && \                        
                           ip link set vni100 up && \
                           ip link set br100 up " 

docker exec -d PE-2 sh -c "ip link add custz type vrf table 52  && \
                           ip link set dev custz up  && \                       
                           ip route add table 32 unreachable default metric 4278198272 && \
                           ip link add br100 type bridge && \
                           ip link set br100 master custz && \                                                  
                           ip addr add 13.13.1.132/24 dev br100 && \
                           ip addr delete 13.13.1.132/25 dev eth3 && \ 
                           ip link add vni100 type vxlan local $lo_pe2 dstport 4789 id 100 nolearning && \
                           ip link set vni100 master br100 addrgenmode none && \
                           ip link set vni100 type bridge_slave neigh_suppress on learning off && \
                           ip link set dev eth3 master br100 && \                     
                           ip link set vni100 up && \
                           ip link set br100 up"


# Router configuration
docker exec -d PE-1 vtysh -c "configure" \
                          -c "router bgp 64502" \
                          -c "address-family l2vpn evpn" \
                          -c "neighbor $lo_pe2 activate" \
                          -c "advertise-all-vni" \
                          -c "!advertise-svi-ip" \
                          -c "exit-address-family" \
                          -c "exit" \
                          -c "router bgp 64502 vrf custz" \
                          -c "address-family ipv4 unicast" \
                          -c "redistribute connected" \
                          -c "exit-address-family" \
                          -c "address-family l2vpn evpn" \
                          -c "advertise ipv4 unicast" \
                          -c "exit-address-family" \
                          -c "exit" 


docker exec -d PE-2 vtysh -c "configure" \
                          -c "router bgp 64502" \
                          -c "address-family l2vpn evpn" \
                          -c "neighbor $lo_pe1 activate" \
                          -c "advertise-all-vni" \
                          -c "!advertise-svi-ip" \
                          -c "exit-address-family" \
                          -c "exit" \
                          -c "router bgp 64502 vrf custz" \
                          -c "address-family ipv4 unicast" \
                          -c "redistribute connected" \
                          -c "exit-address-family" \
                          -c "address-family l2vpn evpn" \
                          -c "advertise ipv4 unicast" \
                          -c "exit-address-family" \
                          -c "exit" 


docker run -itd --name cust_z_a -h cust_z_a --network CustZ_PE1 --ip 13.13.1.15 \
    --cap-add=NET_ADMIN --cap-add SYS_ADMIN ldebian  bash
docker run -itd --name cust_z_b -h cust_z_b --network PE2_CustZ --ip 13.13.1.135  \
    --cap-add=NET_ADMIN --cap-add SYS_ADMIN ldebian bash

docker exec cust_z_a sh -c  "ip route delete default && ip route add default via 13.13.1.8 dev eth0"
docker exec cust_z_b sh -c  "ip route delete default && ip route add default via 13.13.1.132 dev eth0"
