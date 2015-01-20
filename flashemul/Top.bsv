// bsv libraries
import SpecialFIFOs::*;
import Vector::*;
import StmtFSM::*;
import FIFO::*;

// portz libraries
import AxiMasterSlave::*;
import Directory::*;
import CtrlMux::*;
import Portal::*;
import Leds::*;
import ConnectalMemory::*;
import Dma::*;
import DmaUtils::*;
import MemServer::*;

// generated by tool
import InterfaceRequestWrapper::*;
import PlatformRequestWrapper::*;
import DmaConfigWrapper::*;
import InterfaceIndicationProxy::*;
import DmaIndicationProxy::*;
import PlatformIndicationProxy::*;

// defined by user
import Interface::*;
import BlueDBMPlatform::*;
import PlatformInterfaces::*;
import DRAMController::*;

import Clocks          :: *;
import DefaultValue    :: *;
import XilinxVC707DDR3::*;
import Xilinx       :: *;
import XilinxCells :: *;

import AuroraImportVC707::*;
//import AuroraImportVC707_8b10b_X1Y0::*;
//import AuroraImportVC707_X1Y26::*;
//import AuroraImportVC707_X1Y27::*;
import AuroraImportVC707_8b10b_X1Y24::*;
import I2CSimple::*;
import GtxeCommonImport_119::*;

typedef enum {InterfaceIndication, InterfaceRequest, DmaIndication, DmaConfig, PlatformIndication, PlatformRequest} IfcNames deriving (Eq,Bits);

interface BlueDBMTopPins;
	interface DDR3_Pins_VC707 ddr3;
	interface Aurora_Pins_VC707 aurora0;
	interface Aurora_Pins_VC707 aurora1_0;
	/*
	interface Aurora_Pins_VC707 aurora1_2;
	interface Aurora_Pins_VC707 aurora1_3;

	interface Aurora_Pins_VC707 aurora2_0;
	*/
	interface I2C_Pins i2c;
endinterface

typedef 1 NumMasters;
module mkPortalTop#(Clock sys_clk, Reset pci_sys_reset_n, 
		  Vector#(QuadCount, Clock) gtx_clk_p,
		  Vector#(QuadCount, Clock) gtx_clk_n
		) (PortalTop#(addrWidth, 64, BlueDBMTopPins, NumMasters)) 

   provisos(Add#(addrWidth, a__, 52),
	    Add#(b__, addrWidth, 64),
	    Add#(c__, 12, addrWidth),
	    Add#(addrWidth, d__, 44),
	    Add#(e__, c__, 40),
	    Add#(f__, addrWidth, 40));

   DmaIndicationProxy dmaIndicationProxy <- mkDmaIndicationProxy(DmaIndication);
   DmaReadBuffer#(64,32)   dma_read_chan <- mkDmaReadBuffer();
   DmaWriteBuffer#(64,32) dma_write_chan <- mkDmaWriteBuffer();
   Vector#(NumMasters, MemReadClient#(64))   readClients = cons(dma_read_chan.dmaClient, nil);
   Vector#(NumMasters, MemWriteClient#(64)) writeClients = cons(dma_write_chan.dmaClient, nil);
   MemServer#(addrWidth, 64, NumMasters)   dma <- mkMemServer(dmaIndicationProxy.ifc, readClients, writeClients);
   DmaConfigWrapper dmaRequestWrapper <- mkDmaConfigWrapper(DmaConfig,dma.request);

	///////
	PlatformIndicationProxy platformIndicationProxy <- mkPlatformIndicationProxy(PlatformIndication);
	//////
	InterfaceIndicationProxy interfaceIndicationProxy <- mkInterfaceIndicationProxy(InterfaceIndication);

	Interface interfaceRequest <- mkInterfaceRequest(interfaceIndicationProxy.ifc, platformIndicationProxy.ifc, dma_read_chan.dmaServer, dma_write_chan.dmaServer);

   InterfaceRequestWrapper interfaceRequestWrapper <- mkInterfaceRequestWrapper(InterfaceRequest,interfaceRequest.request);
	

   //////////////// test DDR3 stuff start //////////////
   //Clock sys_clk <- mkClockIBUFDS(sys_clk_200mhz, sys_reset_200mhz);
   
   ClockGenerator7Params clk_params = defaultValue();
   clk_params.clkin1_period     = 5.000;       // 200 MHz reference
   clk_params.clkin_buffer      = False;       // necessary buffer is instanced above
   clk_params.reset_stages      = 0;           // no sync on reset so input clock has pll as only load
   clk_params.clkfbout_mult_f   = 5.000;       // 1000 MHz VCO
   clk_params.clkout0_divide_f  = 10;          // unused clock 
   //clk_params.clkout0_divide_f  = 8;//10;          // unused clock 
   clk_params.clkout1_divide    = 5;           // ddr3 reference clock (200 MHz)

   ClockGenerator7 clk_gen <- mkClockGenerator7(clk_params, clocked_by sys_clk, reset_by pci_sys_reset_n);
   Clock ddr_clk = clk_gen.clkout0;
   Reset rst_n <- mkAsyncReset( 4, pci_sys_reset_n, ddr_clk );
   Reset ddr3ref_rst_n <- mkAsyncReset( 4, rst_n, clk_gen.clkout1 );
   //Reset ddr3ref_rst_n <- mkAsyncReset( 1, pci_sys_reset_n, clk_gen.clkout1 );

   DDR3_Configure ddr3_cfg = defaultValue;
   //ddr3_cfg.reads_in_flight = 2;   // adjust as needed
   ddr3_cfg.reads_in_flight = 24;   // adjust as needed
   //ddr3_cfg.fast_train_sim_only = False; // adjust if simulating
   DDR3_Controller_VC707 ddr3_ctrl <- mkDDR3Controller_VC707(ddr3_cfg, clk_gen.clkout1, clocked_by clk_gen.clkout1, reset_by ddr3ref_rst_n);

   // ddr3_ctrl.user needs to connect to user logic and should use ddr3clk and ddr3rstn
   Clock ddr3clk = ddr3_ctrl.user.clock;
   Reset ddr3rstn = ddr3_ctrl.user.reset_n;
   DRAMControllerIfc dramController <- mkDRAMController(ddr3_ctrl.user, clocked_by ddr_clk, reset_by rst_n);
   
   ///////////////////////////// DDR3 end

	Clock cur_clk <- exposeCurrentClock;
	Reset cur_rst_n <- exposeCurrentReset;

	//////////////////////////// Aurora Start

	MakeResetIfc auroraRst <- mkReset(1, False, cur_clk);
	Reset auroraRstE <- mkResetEither(auroraRst.new_rst, cur_rst_n);
	Vector#(QuadCount, Clock) gtx_clks;
	for (Integer i = 0; i < valueOf(QuadCount); i = i + 1) begin
		gtx_clks[i] <- mkClockIBUFDS_GTE2(True, gtx_clk_p[i], gtx_clk_n[i]);
	end
	/*
	gtx_clks[0] <- mkClockIBUFDS_GTE2(True, gtx_clk_p[0], gtx_clk_n[0]);
	gtx_clks[1] <- mkClockIBUFDS_GTE2(True, gtx_clk_p[1], gtx_clk_n[1]);
	gtx_clks[2] <- mkClockIBUFDS_GTE2(True, gtx_clk_p[2], gtx_clk_n[2]);
	*/

	Vector#(AuroraPorts, AuroraIfc) auroras;
	Vector#(AuroraIntraPorts, AuroraIfc32) auroraIntras;
	Aurora_V7 auroraImport0 <- mkAuroraWrapper(gtx_clks[0], sys_clk, auroraRstE);//cur_rst_n);
	AuroraIfc aurora0 <- mkAurora(auroraImport0, auroraRst);
	auroras[0] = aurora0;
	
/*
//	GtxeCommonIfc gtxe119 <- mkGtxeCommonImport_119(gtx_clks[1], cur_clk);
	Aurora_V7 auroraImport1_0 <- mkAuroraWrapper_X1Y24(gtx_clks[1], cur_clk, auroraRstE, gtxe119.qpllclk, gtxe119.qpllrefclk);//cur_rst_n);
	AuroraIfc aurora1_0 <- mkAurora(auroraImport1_0, auroraRst);
	auroras[1] = aurora1_0;
	
	Aurora_V7 auroraImport1_2 <- mkAuroraWrapper_X1Y26(gtx_clks[1], cur_clk, auroraRstE, gtxe119.qpllclk, gtxe119.qpllrefclk);//cur_rst_n);
	AuroraIfc aurora1_2 <- mkAurora(auroraImport1_2, auroraRst);
	auroras[2] = aurora1_2;
	
	Aurora_V7 auroraImport1_3 <- mkAuroraWrapper_X1Y27(gtx_clks[1], cur_clk, auroraRstE, gtxe119.qpllclk, gtxe119.qpllrefclk);//cur_rst_n);
	AuroraIfc aurora1_3 <- mkAurora(auroraImport1_3, auroraRst);
	auroras[3] = aurora1_3;
*/
	MakeResetIfc sys_clk_rst <- mkReset(4, False, sys_clk);
	Reset rst200 = sys_clk_rst.new_rst;
	let clockdiv4 <- mkClockDivider(4, clocked_by sys_clk, reset_by rst200);
	Clock clk50 = clockdiv4.slowClock;
	MakeResetIfc rst50ifc <- mkReset(4, False, clk50);
	Reset rst50 = rst50ifc.new_rst;

	Aurora_V7_32 auroraImport1_0 <- mkAuroraWrapper_8b10b_X1Y24(gtx_clks[1], clk50, rst50);//cur_clk, auroraRstE);
	AuroraIfc32 aurora1_0 <- mkAurora32(auroraImport1_0, auroraRst);
	auroraIntras[0] = aurora1_0;


	//////////////////////////// Aurora End

	/////FIXME: Change it to use BSV's vanilla distributed I2C
	Vector#(I2C_Count,I2C_User) i2c;
	I2C i2c0 <- mkI2C(416); //125/417 = 299khz/3 = 100khz i2c clk
	i2c[0] = i2c0.user;
	
	BlueDBMPlatformIfc bluedbm <- mkBlueDBMPlatform(interfaceRequest.flash, interfaceRequest.host, dramController, auroras, auroraIntras, i2c);
	/*
	rule feedDebug;
		bluedbm.auroraDbgData(auroraImport1_0.debug_out);
	endrule
	*/
   
   PlatformRequestWrapper platformRequestWrapper <- mkPlatformRequestWrapper(PlatformRequest, bluedbm.request);
   
   Vector#(6,StdPortal) portals;
   portals[1] = interfaceRequestWrapper.portalIfc;
   portals[0] = interfaceIndicationProxy.portalIfc; 
   portals[3] = dmaRequestWrapper.portalIfc;
   portals[2] = dmaIndicationProxy.portalIfc; 
   portals[5] = platformRequestWrapper.portalIfc;
   portals[4] = platformIndicationProxy.portalIfc;
   
   StdDirectory dir <- mkStdDirectory(portals);
   let ctrl_mux <- mkSlaveMux(dir,portals);
   //let interrupt_mux <- mkInterruptMux(portals);

   interface interrupt = getInterruptVector(portals);
   interface slave = ctrl_mux;
   interface masters = dma.masters;
   interface leds = default_leds;

   //interface DDR3_Pins_VC707 pins = ddr3_ctrl.ddr3;
   interface BlueDBMTopPins pins;
	   interface DDR3_Pins_VC707 ddr3 = ddr3_ctrl.ddr3;
	   interface Aurora_Pins_VC707 aurora0 = auroraImport0.aurora;

		interface Aurora_Pins_VC707 aurora1_0 = auroraImport1_0.aurora;
		/*
	   interface Aurora_Pins_VC707 aurora1_2 = auroraImport1_2.aurora;
	   interface Aurora_Pins_VC707 aurora1_3 = auroraImport1_3.aurora;
	   interface Aurora_Pins_VC707 aurora2_0 = auroraImport2_0.aurora;
	   */

	   interface I2C_Pins i2c = i2c0.i2c;
   endinterface

endmodule


