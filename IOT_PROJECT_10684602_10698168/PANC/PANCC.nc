#include "Timer.h"
#include "printf.h"

#include "PANC.h"


module PANCC @safe() {
  uses {
  
    /****** INTERFACES *****/
    interface Boot;
    interface Receive;
    interface AMSend;
    interface Timer<TMilli> as Timer0;
    interface Timer<TMilli> as Timer1; // used to separate the multiple publish messages
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
  bool connack_sent = FALSE;
  
  bool connected[8] = {FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE};
  
  // subscribe variables
  bool suback_sent = FALSE;
  
  // ex. for node 2, we have subscribed_topics[0]
  // subscribed_topics[0][0] is temperature,
  // subscribed_topics[0][1] is humidity,
  // subscribed_topics[0][2] is luminosity.
  bool subscribed_topics[8][3] = {{FALSE, FALSE, FALSE}, {FALSE, FALSE, FALSE}, {FALSE, FALSE, FALSE},
  								  {FALSE, FALSE, FALSE}, {FALSE, FALSE, FALSE}, {FALSE, FALSE, FALSE},
  								  {FALSE, FALSE, FALSE}, {FALSE, FALSE, FALSE}};
  
  // publish variables
  bool publish_sent = FALSE;
  
  uint16_t current_publish_topic;
  uint16_t current_publish_payload;
  int current_publisher;
  
  int count = 0;
  
  
  // functions to send messages
  
  void send_connack_message(int id){
  	msg_t *connack_message;
  	
  	printf("sending a connack message to node: %d\n", id);
  	
    connack_message = (msg_t*)call Packet.getPayload(&packet_buf, sizeof(msg_t));
    
    connack_message->type = CONNACK;
    
    // send the message to node with the id specified
    generate_send(id, &packet_buf, CONNACK);
    
  	// reset the connack_sent flag
	connack_sent = FALSE;
  }
  
  void send_suback_message(int id){
    msg_t *connack_message;
  	
  	printf("sending a suback message to node: %d\n", id);
  	
    connack_message = (msg_t*)call Packet.getPayload(&packet_buf, sizeof(msg_t));
    
    connack_message->type = SUBACK;
    
    // send the message to node with the id specified
    generate_send(id, &packet_buf, SUBACK);
    
  	// reset the suback_sent flag
	suback_sent = FALSE;
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
  	if (type == CONNACK && !connack_sent){
  	  	connack_sent = TRUE;
  		call Timer0.startOneShot(time_delays[TOS_NODE_ID-1]);
  		queued_packet = *packet;
  		queue_addr = address;
  	}
  	else if (type == SUBACK && !suback_sent){
  	  	suback_sent = TRUE;
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
		printf("sending packet\n");
		locked = TRUE;
		return TRUE;
	  }
	}
	return FALSE;
  }
  
  
  event void Boot.booted() {
    printf("application booted\n");
    
    call AMControl.start();
  }

  event void AMControl.startDone(error_t err) {
	if(err == SUCCESS) {
	  printf("PANC radio start done\n");
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
	if(count < 8){
      if(count != current_publisher && subscribed_topics[count][current_publish_topic] == TRUE){
        send_publish_message(count+2, current_publish_topic, current_publish_payload);
      }
      
      count += 1;
      call Timer1.startOneShot(50);
    }
  }
  
  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    msg_t* message = (msg_t*)payload;
    uint16_t id = message->id;
	
	if(message->type == CONNECT){
	  printf("node %d requested to connect\n", id);
      
	  if(connected[id-2] == FALSE){
	    // we consider the mote who sent the connect to be connected now
	    connected[id-2] = TRUE;
	    
	    // reply with the connack
	    send_connack_message(id);
 	  }
	  else{
	    printf("node %d already connected, resending the connack\n", id);
	    
	    // if the mote is already connected, resend the connack
	    send_connack_message(id);
	  }
    }else if(message->type == SUBSCRIBE){
      if(connected[id-2] == FALSE){
        printf("node %d not connected, dropping the subscribe message\n", id);
      }
      else{
        printf("node %d requested to subscribe to topic %d\n", id, message->topic);
        // subscribe the mote to the specified topic
        subscribed_topics[id-2][message->topic] = TRUE;
        
        // reply with the suback
        send_suback_message(id);
      }
    }
    else if(message->type == PUBLISH){
      if(connected[id-2] == FALSE){
        printf("node %d not connected, dropping the publish message\n", id);
      }
      else{
        printf("publish message received by node %d with topic: %d and payload: %d\n", id, message->topic, message->payload);
        // this printf is used to update the data on thingspeak, it is important so we flush the output immediately
        printfflush();
        
        // check who is subscribed to the topic specified and send the publish message to them
        count = 0;
        
        current_publish_topic = message->topic;
        current_publish_payload = message->payload;
        current_publisher = id;
        
        call Timer1.startOneShot(15);
      }
    }
	
    return bufPtr;
  }

  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
    if(error == SUCCESS){
	  printf("Packet sent\n");
	}
	else{
	  printf("there was an error sending the packet\n");
	}
	  
	locked = FALSE;
  }
}




