#include "interface.h"

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>   

#ifndef BSIM
	bool verbose = false;
#else
	bool verbose = true;
#endif

sem_t wait_sem;

int srcAllocs[DMA_BUFFER_COUNT];
int dstAllocs[DMA_BUFFER_COUNT];
unsigned int ref_srcAllocs[DMA_BUFFER_COUNT];
unsigned int ref_dstAllocs[DMA_BUFFER_COUNT];
unsigned int* srcBuffers[DMA_BUFFER_COUNT];
unsigned int* dstBuffers[DMA_BUFFER_COUNT];

unsigned int* writeBuffers[WRITE_BUFFER_COUNT];
unsigned int* readBuffers[READ_BUFFER_COUNT];

pthread_mutex_t flashReqMutex;
pthread_cond_t flashReqCond;

int rnumBytes = (1 << (10 +4))*READ_BUFFER_WAYS; //16KB buffer, to be safe
int wnumBytes = (1 << (10 +4))*WRITE_BUFFER_WAYS; //16KB buffer, to be safe
size_t ralloc_sz = rnumBytes*sizeof(unsigned char);
size_t walloc_sz = wnumBytes*sizeof(unsigned char);

const char* log_prefix = "\t\tLOG: ";

GeneralRequestProxy *generalRequest = 0;
GeneralIndication *generalIndication = 0;

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}


void interface_init() {
	generalRequest = new GeneralRequestProxy(GeneralRequestPortal);
	generalIndication = new GeneralIndication(GeneralIndicationPortal);
	
	pthread_mutex_init(&flashReqMutex, NULL);
	pthread_cond_init(&flashReqCond, NULL);
}

void setAuroraRouting2(int myid, int src, int dst, int port1, int port2) {
	if ( myid != src ) return;

	for ( int i = 0; i < 8; i ++ ) {
		if ( i % 2 == 0 ) { 
			generalRequest->setAuroraExtRoutingTable(dst,port1, i);
		} else {
			generalRequest->setAuroraExtRoutingTable(dst,port2, i);
		}
	}
}

void auroraifc_start(int myid) {
	generalRequest->setNodeId(myid);
	generalRequest->auroraStatus(0);

	//This is not strictly required
	for ( int i = 0; i < 8; i++ ) 
		generalRequest->setAuroraExtRoutingTable(myid,0,i);

	// This is set up such that all nodes can one day 
	// read the same routing file and apply it
	setAuroraRouting2(myid, 0,1, 0,2);
	setAuroraRouting2(myid, 0,2, 1,3);
	setAuroraRouting2(myid, 0,3, 1,3);

	setAuroraRouting2(myid, 1,0, 0,1);
	setAuroraRouting2(myid, 1,2, 0,1);
	setAuroraRouting2(myid, 1,3, 0,1);
	
	setAuroraRouting2(myid, 2,0, 0,3);
	setAuroraRouting2(myid, 2,1, 0,3);
	setAuroraRouting2(myid, 2,3, 0,3);

	setAuroraRouting2(myid, 3,0, 1,2);
	setAuroraRouting2(myid, 3,1, 1,2);
	setAuroraRouting2(myid, 3,2, 0,3);

	usleep(100);
}


void generalifc_start(int datasource) {
	generalRequest->start(datasource);
}

void generalifc_readRemotePage(int myid) {
  int dstid = ~myid;
  generalRequest->auroraStatus(0);
  generalRequest->sendData(1, dstid, 0);
}
void generalifc_latencyReport() {
	for ( int i = 0; i < 16; i++ ) {
		float tot = generalIndication->timediff[i];
		float avg = tot/generalIndication->timediffcnt[i];
		printf( "%d: %f\n",i,avg );
	}
}

void GeneralIndication::readPage(uint64_t addr, uint32_t dstnode, uint32_t datasource) {
	printf( "readpage req! -> %d\n", dstnode ); fflush(stdout);
}

