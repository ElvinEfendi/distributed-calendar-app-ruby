Coursework: Distributed calendar app
=============================

In this project I've implemented simple distributed calendar network in order to gain practical knowledge on Distributed Systems,
XML RPC, Token Ring and Ricart Agrawala algorithms. Another clone of the project is written in 
[Java](https://github.com/ElvinEfendi/distributed-calendar-app-java) and these two applications can be
run in one calendar network at the same time.

Instructions to run the application:

 - Edit and set configuration in config.yml

 - To start a new network run calendar_network.rb.
   Note that in this mode you will still not be able to add or modify appointments.
 
 - To fully use the distributed application calendar_network.rb using host and port of one of the online node as argument

 - If calendar_network program is terminated your node will automatically be logged out from the network 

 - To do operations on appointments run the client appointments_controller.rb.
   If you are not running client your node can still be online and serving to the other nodes in the network

 - Set your preferred mutual exclusion algorithm in config.yml:
   me_algorithm: token_ring
   or
   me_algorithm: ricart_agrawala. REQUIREMENT: every node in the same network has to use same me_algorithm
