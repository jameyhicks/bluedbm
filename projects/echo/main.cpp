/* Copyright (c) 2013 Quanta Research Cambridge, Inc
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
#include <stdio.h>
#include <sys/mman.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <monkit.h>
#include <semaphore.h>

#include <list>
#include <time.h>


#include "connectal.h"
#include "interface.h"

int main(int argc, const char **argv)
{
	unsigned long myid = 0;
	char* userhostid = getenv("BDBM_ID");
	if ( userhostid != NULL ) {
	  myid = strtoul(userhostid, NULL, 0);
	}

	interface_init();
	printf( "Done initializing hw interfaces\n" ); fflush(stdout);

	printf( "initializing aurora with node id %ld\n", myid ); fflush(stdout);
	auroraifc_start(myid);

	/////////////////////////////////////////////////////////

	if ( sem_init(&wait_sem, 1, 0) ) {
		//error
		fprintf(stderr, "sem_init failed!\n" );
	}

	sleep(10);
	printf ( "sending start msg\n" ); fflush(stdout);
	generalifc_start(/*datasource*/1);
	//auroraifc_sendTest();

	for (int i = 0; i < 10; i++) {
	  generalifc_readRemotePage(myid);
	  sleep(1);
	}
	sleep(20);

	exit(0);
}
