docker rm -f PE-1
docker rm -f LSR-1
docker rm -f LSR-2
docker rm -f PE-2
docker rm -f cust_x_a
docker rm -f cust_x_b
docker rm -f cust_z_a
docker rm -f cust_z_b

docker network rm CustX_PE1
docker network rm CustZ_PE1
docker network rm PE2_CustX
docker network rm PE2_CustZ
docker network rm  LSR1_PE2
docker network rm  LSR2_PE2
docker network rm  PE1_LSR1
docker network rm  PE1_LSR2
#docker network rm CustX_B_SNET

sudo rm -r configs