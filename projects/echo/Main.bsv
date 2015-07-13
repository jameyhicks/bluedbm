// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import FIFOF::*;
import FIFO::*;
import BRAMFIFO::*;
import BRAM::*;
import GetPut::*;
import ClientServer::*;
import BuildVector::*;
import Vector::*;
import List::*;

import ConnectalMemory::*;
import MemTypes::*;
import Pipe::*;

import Clocks :: *;
import Xilinx       :: *;
`ifndef BSIM
import XilinxCells ::*;
`endif

import AuroraImportFmc1::*;

import ControllerTypes::*;
import FlashCtrlVirtex::*;
import FlashCtrlModel::*;

import AuroraExtArbiterBar::*;
import AuroraExtEndpoint::*;
import AuroraExtImport::*;
//import AuroraExtImport117::*;
import AuroraCommon::*;

import StreamingSerDes::*;

interface GeneralRequest;
   method Action setAuroraExtRoutingTable(Bit#(32) node, Bit#(32) portidx, Bit#(32) portsel);
   method Action setNodeId(Bit#(32) nodeId);
   method Action start(Bit#(32) dummy);

   method Action sendData(Bit#(32) count, Bit#(5) target, Bit#(32) stride);
   method Action auroraStatus(Bit#(32) dummy);
endinterface

interface GeneralIndication;
   method Action readPage(Bit#(64) addr, Bit#(32) dstnod, Bit#(32) datasource);
   method Action recvSketch(Bit#(32) sketch, Bit#(32) latency);
   method Action receive(Bit#(64) payload, Bit#(8) src);
   method Action hexDump(Bit#(32) hex);
   method Action mismatch(Bit#(32) hex, Bit#(32) hex2);
   method Action timeDiffDump(Bit#(32) diff, Bit#(32) ttype);
   method Action hardError(Bit#(32) portnum);
   method Action auroraStatus(Bit#(32) linkUp, Bit#(32) softErrorCount0, Bit#(32) softErrorCount1, Bit#(32) softErrorCount2, Bit#(32) softErrorCount3);
endinterface

interface MainIfc;
   interface GeneralRequest request;

   interface Vector#(AuroraExtPerQuad, Aurora_Pins#(1)) aurora_ext;
   interface Aurora_Clock_Pins aurora_quad119;
endinterface

typedef enum {Flash, Host, DRAM, PageCache} DataSource deriving (Bits,Eq);

typedef enum {Read,Write,Erase} CmdType deriving (Bits,Eq);
//typedef struct { Bit#(5) channel; Bit#(5) chip; Bit#(8) block; Bit#(8) page; CmdType cmd; Bit#(8) tag; Bit#(8) bufidx;} FlashCmd deriving (Bits,Eq);

module mkMain#(GeneralIndication indication, Clock clk250, Reset rst250)(MainIfc);

   Clock curClk <- exposeCurrentClock;
   Reset curRst <- exposeCurrentReset;

   Reg#(Bool) started <- mkReg(False);
   Reg#(Bit#(HeaderFieldSz)) myNodeId <- mkReg(1);

`ifndef BSIM
   ClockDividerIfc auroraExtClockDiv5 <- mkDCMClockDivider(5, 4, clocked_by clk250);
   Clock clk50 = auroraExtClockDiv5.slowClock;
`else
   Clock clk50 = curClk;
`endif

   AuroraEndpointIfc#(Bit#(128)) aend1 <- mkAuroraEndpointDynamic(100, 100, 100);
   AuroraEndpointIfc#(Bit#(128)) aend2 <- mkAuroraEndpointStatic(128, 64);
   let auroraList = vec(aend2.cmd, aend1.cmd);
	
   GtxClockImportIfc gtx_clk_119 <- mkGtxClockImport;
   AuroraExtIfc auroraExt119 <- mkAuroraExt(gtx_clk_119.gtx_clk_p_ifc, gtx_clk_119.gtx_clk_n_ifc, clk50);

   //AuroraExtArbiterBarIfc auroraExtArbiter <- mkAuroraExtArbiterBar(auroraExt119.user, auroraList);

   Reg#(Bit#(32)) latencyCounter <- mkReg(0);
   rule incLatencyCounter;
      latencyCounter <= latencyCounter + 1;
   endrule

   Vector#(4, Reg#(Bit#(32))) sendDataCount <- replicateM(mkReg(0));
   Reg#(HeaderField) sendDataTarget <- mkReg(0);
   for (Integer link = 0; link < 4; link = link + 1)
      rule sendAuroraData if(sendDataCount[link] > 0 );
	 sendDataCount[link] <= sendDataCount[link] - 1;
	 let ptype = 0;
	 if (myNodeId == 1)
	    ptype = 2;
	 Payload data = zeroExtend({sendDataCount[link],8'hbb});
	 $display("sendAuroraData link=%d data=%h", link, data);
	 auroraExt119.user[link].send.put(AuroraPacket { payload: data, dst: sendDataTarget, src: myNodeId, ptype: fromInteger(link)});
      endrule

   for (Integer link = 0; link < 4; link = link + 1) begin
      Reg#(Bit#(32)) recvDataCount <- mkReg(0);
      rule recvAuroraData;
	 recvDataCount <= recvDataCount + 1;

	 let rst <- auroraExt119.user[link].receive.get();
	 let data = rst.payload;
	 let src = rst.src;

	 $display("recvAuroraData link=%d data=%h", link, data);
	 indication.receive(truncate(data), extend(src));
      endrule
   end
	
   Reg#(Bit#(32)) lastDataIn2 <- mkReg(0);
   Reg#(Bit#(32)) aend2Throttle <- mkReg(0);

   interface GeneralRequest request;

      method Action sendData(Bit#(32) count, Bit#(5) target, Bit#(32) stride);
	 for (Integer link = 0; link < 4; link = link + 1) begin
	    sendDataCount[link] <= count;
	 end
	 sendDataTarget <= target;
      endmethod
      method Action setAuroraExtRoutingTable(Bit#(32) node, Bit#(32) portidx, Bit#(32) portsel);
	 //auroraExtArbiter.setRoutingTable(truncate(node), truncate(portidx), truncate(portsel));
      endmethod
      method Action start(Bit#(32) dummy);
	 started <= True;
      endmethod
      method Action setNodeId(Bit#(32) nodeId);
	 myNodeId <= truncate(nodeId);
	 //auroraExtArbiter.setMyId(truncate(netid));
	 auroraExt119.setNodeIdx(truncate(nodeId));
      endmethod
      method Action auroraStatus(Bit#(32) dummy);
	 indication.auroraStatus({
				  0,
				  auroraExt119.user[3].channel_up,
				  auroraExt119.user[2].channel_up,
				  auroraExt119.user[1].channel_up,
				  auroraExt119.user[0].channel_up
				  },
				 auroraExt119.user[0].soft_err_count,
				 auroraExt119.user[1].soft_err_count,
				 auroraExt119.user[2].soft_err_count,
				 auroraExt119.user[3].soft_err_count);
      endmethod
   endinterface

   interface Aurora_Pins aurora_ext = auroraExt119.aurora;
   interface Aurora_Clock_Pins aurora_quad119 = gtx_clk_119.aurora_clk;
endmodule

