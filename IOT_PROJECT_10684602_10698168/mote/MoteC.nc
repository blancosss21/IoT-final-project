#include <stdlib.h>

#include "Timer.h"
#include "printf.h"

#include "Mote.h"


module MoteC @safe() {
  uses {
  
    /****** INTERFACES *****/
    interface Boot;
    interface Receive;
    interface AMSend;
    interface Timer<TMilli> as Timer0;
    interface Timer<TMilli> as Timer1; // used for waiting the ack of connect messages
    interface Timer<TMilli> as Timer2; // used for waiting the ack of subscribe messages
    interface Timer<TMilli> as Timer3; // used simulation
    interface SplitControl as AMControl;
    interface Packet;
  }
}
implementation {

  message_t packet_buf;
  
  // Variables to store the message to send
  message_t queued_packet;
  uint16_t queue_addr;
  
  uint16_t time_delays[9] = {1, 107, 163, 220, 289, 345, 409, 463, 520}; //Time delay in milli seconds
  
  bool locked;
  
  bool actual_send (uint16_t address, message_t* packet);
  bool generate_send (uint16_t address, message_t* packet, uint16_t type);
  
  // connection variables
  bool connect_sent = FALSE;
  
  bool connect_acked = FALSE;
  
  // subscribe variables
  bool subscribe_sent = FALSE;
  
  bool subscribe_acked = FALSE;
  								  
  uint16_t current_subscribe_topic;
  
  // publish variables
  bool publish_sent = FALSE;
  
  // simulation variables
  uint16_t simulation = 0;
  
  
  // functions to send messages
  
  void send_connect_message(){
  	msg_t *connect_message;
  	
  	printf("sending a connect message\n");
  	
    connect_message = (msg_t*)call Packet.getPayload(&packet_buf, sizeof(msg_t));
    
    connect_message->id = TOS_NODE_ID;
    connect_message->type = CONNECT;
    
    // send the message to node 1 (PANC)
    generate_send(1, &packet_buf, CONNECT);
	  	
  	// reset the connect_sent flag
	connect_sent = FALSE;
  	
    connect_acked = FALSE;
    
  	// wait 1s to receive an ack for the connect message
  	call Timer1.startOneShot(2000);
  }
  
  void send_subscribe_message(uint16_t topic){
  	msg_t *subscribe_message;
  	
  	printf("sending a subscribe message to topic %d\n", topic);
  	
    subscribe_message = (msg_t*)call Packet.getPayload(&packet_buf, sizeof(msg_t));
    
    subscribe_message->id = TOS_NODE_ID;
    subscribe_message->type = SUBSCRIBE;
    subscribe_message->topic = topic;
    
    // set the current subscribe topic to the one specified
    current_subscribe_topic = topic;
    
    // send the message to node 1 (PANC)
    generate_send(1, &packet_buf, SUBSCRIBE);
    
    // reset the subscribe_sent flag
	subscribe_sent = FALSE;
	
	subscribe_acked = FALSE;
  	
  	// wait 2s to receive an ack for the subscribe message
  	call Timer2.startOneShot(2000);
  }
  
  void send_publish_message(int id, uint16_t topic, uint16_t payload){
    msg_t *publish_message;
  	
  	printf("sending a publish message to node %d\ntopic of the message: %d, payload: %d\n", id, topic, payload);
  	
    publish_message = (msg_t*)call Packet.getPayload(&packet_buf, sizeof(msg_t));
    
    publish_message->id = TOS_NODE_ID;
    publish_message->type = PUBLISH;
    publish_message->topic = topic;
    publish_message->payload = payload;
    
    
    generate_send(id, &packet_buf, PUBLISH);
    
    // reset the publish_sent flag
    publish_sent = FALSE;
  }
  
  
  bool generate_send (uint16_t address, message_t* packet, uint16_t type){
  	if (call Timer0.isRunning()){
  		return FALSE;
  	}
  	else{
  	if(type == CONNECT && !connect_sent){
  		connect_sent = TRUE;
  		call Timer0.startOneShot(time_delays[TOS_NODE_ID-1]);
  		queued_packet = *packet;
  		queue_addr = address;
  	}
  	else if (type == SUBSCRIBE && !subscribe_sent){
  	  	subscribe_sent = TRUE;
  		call Timer0.startOneShot(time_delays[TOS_NODE_ID-1]);
  		queued_packet = *packet;
  		queue_addr = address;
  	}
    else if (type == PUBLISH && !publish_sent){
    	publish_sent = TRUE;
  		call Timer0.startOneShot(time_delays[TOS_NODE_ID-1]);
  		queued_packet = *packet;
  		queue_addr = address;
  	}
  	}
  	return TRUE;
  }
  
  event void Timer0.fired() {
  	actual_send (queue_addr, &queued_packet);
  }
  
  bool actual_send(uint16_t address, message_t* packet){
	if(!locked){
	  if(call AMSend.send(address, packet, sizeof(msg_t)) == SUCCESS) {
		printf("Sending packet\n");
		locked = TRUE;
		return TRUE;
	  }
	}
	return FALSE;
  }
  
  
  event void Boot.booted() {
    printf("application booted\n");
    srand(TOS_NODE_ID);
    call AMControl.start();
  }

  event void AMControl.startDone(error_t err) {
	if(err == SUCCESS) {
	  printf("radio start done\n");
	  	
	  	// wait 2s and then send a connect message
	  	call Timer3.startOneShot(2000);
	}
	else{
	  printf("radio failed to start, retrying...\n");
	  
	  call AMControl.start();
	}
  }

  event void AMControl.stopDone(error_t err) {
	printf("radio stopped\n");
  }
  
  event void Timer1.fired() {
	// timer used to wait for acks of connect message
	if(connect_acked == FALSE){
		printf("connack threshold exceeded, retrying connection...\n");
		
		send_connect_message();
	}
  }
  
  event void Timer2.fired() {
	// timer used to wait for acks of subscribe messages
	if(subscribe_acked == FALSE){
      printf("suback threshold exceeded, retrying subscription...\n");
      
      send_subscribe_message(current_subscribe_topic);
	}
  }
  
  event void Timer3.fired() {
    uint16_t generated_topic;
    uint16_t generated_payload;
    // timer used for simulation purposes
    
    // simulation == 0 is the connect phase
    // simulation == 1, 2 is the subscribe phase
    // simulation == 3 onward is the publish phase
    
    if(simulation == 0){
      send_connect_message();
    }
    else if(simulation == 1 || simulation == 2){
      // generate a topic
      generated_topic = abs(rand()%3);
      
      // because topics are random it could happen that sometimes the two generated topics of a mote coincide
      send_subscribe_message(generated_topic);
    }
    else if(simulation >= 3 && simulation < 5){
      // generate random topic
      generated_topic = abs(rand()%3);
      
      // generate random payload
      generated_payload = abs(rand()%80) + 20;
      printf("publish message generated with topic: %d and payload: %d\n", generated_topic, generated_payload);
      
      send_publish_message(1, generated_topic, generated_payload);
      
      // proceed with the simulation
      simulation += 1;
      call Timer3.startOneShot(1000*(abs(rand()%3) + 1));
    }
  }

  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    msg_t* message = (msg_t*)payload;
    if(message->type == CONNACK){
      printf("connack message received\n");
      
      connect_acked = TRUE;
      
      // proceed with the simulation
      simulation += 1;
      
      call Timer3.startOneShot(1000*(abs(rand()%3) + 1));
    }
    else if(message->type == SUBACK){
      printf("suback message received\n");
      
      subscribe_acked = TRUE;
      
      // proceed with the simulation
      simulation += 1;
      
      call Timer3.startOneShot(1000*(abs(rand()%3) + 1));
    }
    else if(message->type == PUBLISH){
      // if the publish is not coming from the PANC, drop it
      if(message->id == 1){
        printf("publish message received with topic: %d and payload: %d\n", message->topic, message->payload);
      }
    }
	
    return bufPtr;
  }

  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
    if(error == SUCCESS){
	  printf("packet sent\n");
	}
	else{
	  printf("there was an error sending the packet\n");
	}
	  
	locked = FALSE;
  }
}




