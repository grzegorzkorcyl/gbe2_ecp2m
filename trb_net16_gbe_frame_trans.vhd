LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;
use work.trb_net16_hub_func.all;

entity trb_net16_gbe_frame_trans is
port (
	CLK					: in	std_logic;
	RESET				: in	std_logic;
	LINK_OK_IN              : in    std_logic;  -- gk 03.08.10
	TX_MAC_CLK			: in	std_logic;
	TX_EMPTY_IN			: in	std_logic;
	START_OF_PACKET_IN	: in	std_logic;
	DATA_ENDFLAG_IN		: in	std_logic; -- (8) is end flag, rest is only for TSMAC

	TX_FIFOAVAIL_OUT	: out	std_logic;
	TX_FIFOEOF_OUT		: out	std_logic;
	TX_FIFOEMPTY_OUT	: out	std_logic;
	TX_DONE_IN			: in	std_logic;
	TX_DISCFRM_IN		:	in std_logic;
	-- Debug
	BSM_INIT_OUT		: out	std_logic_vector(3 downto 0);
	BSM_MAC_OUT			: out	std_logic_vector(3 downto 0);
	BSM_TRANS_OUT		: out	std_logic_vector(3 downto 0);
	DBG_RD_DONE_OUT		: out	std_logic;
	DBG_INIT_DONE_OUT	: out	std_logic;
	DBG_ENABLED_OUT		: out	std_logic;
	DEBUG_OUT			: out	std_logic_vector(63 downto 0)
);
end trb_net16_gbe_frame_trans;

-- FifoRd ?!?

architecture trb_net16_gbe_frame_trans of trb_net16_gbe_frame_trans is

-- attribute HGROUP : string;
-- attribute HGROUP of trb_net16_gbe_frame_trans : architecture  is "GBE_frame_trans";

component mac_init_mem is
port (
	Address		: in	std_logic_vector(5 downto 0); 
	OutClock	: in	std_logic; 
	OutClockEn	: in	std_logic; 
	Reset		: in	std_logic; 
	Q			: out	std_logic_vector(7 downto 0)
);
end component;

attribute syn_encoding	: string;

type macInitStates is (I_IDLE, I_INCRADDRESS, I_PAUSE, I_WRITE, I_PAUSE2, I_READ, I_PAUSE3, I_ENDED);
signal macInitState, macInitNextState : macInitStates;
attribute syn_encoding of macInitState: signal is "safe,gray";
signal bsm_init			: std_logic_vector(3 downto 0);
	
type macStates is (M_RESETING, M_IDLE, M_INIT);
signal macCurrentState, macNextState : macStates;
signal bsm_mac			: std_logic_vector(3 downto 0);
	
type transmitStates is (T_IDLE, T_TRANSMIT, T_WAITFORFIFO);
signal transmitCurrentState, transmitNextState : transmitStates;
attribute syn_encoding of transmitCurrentState: signal is "safe,gray";
signal bsm_trans		: std_logic_vector(3 downto 0);

signal tx_fifoavail_i	: std_logic;
signal tx_fifoeof_i		: std_logic;

-- host interface signals
signal hcs_n_i			: std_logic;
signal hwrite_n_i		: std_logic;
signal hread_n_i 		: std_logic;

-- MAC INITIALIZATION signals
signal macInitMemAddr	: std_logic_vector(5 downto 0);
signal macInitMemQ		: std_logic_vector(7 downto 0);
signal macInitMemEn		: std_logic;
signal reading_done		: std_logic;
signal init_done		: std_logic;
signal enabled			: std_logic;
signal addrSig			: std_logic_vector(5 downto 0);
signal addr2			: std_logic_vector(5 downto 0);
signal resetAddr		: std_logic;

signal FifoEmpty		: std_logic;
signal debug			: std_logic_vector(63 downto 0);

begin

-- Fakes
debug <= (others => '0');


TransmitStateMachineProc : process (TX_MAC_CLK)
begin
	if rising_edge(TX_MAC_CLK) then
		if (RESET = '1') or (LINK_OK_IN = '0') then -- gk 01.10.10
			transmitCurrentState <= T_IDLE;
		else
			transmitCurrentState <= transmitNextState;
		end if;
	end if;
end process TransmitStatemachineProc;

--TransmitStateMachine : process (transmitCurrentState, macCurrentState, START_OF_PACKET_IN, DATA_ENDFLAG_IN, TX_DONE_IN)
TransmitStateMachine : process (transmitCurrentState, START_OF_PACKET_IN, DATA_ENDFLAG_IN, TX_DONE_IN)
begin
	case transmitCurrentState is
		when T_IDLE =>
			bsm_trans <= x"0";
			if (START_OF_PACKET_IN = '1') then  --and (macCurrentState = M_IDLE)) then
				transmitNextState <= T_TRANSMIT;
			else
				transmitNextState <= T_IDLE;
			end if;
		when T_TRANSMIT =>
			bsm_trans <= x"1";
			if (DATA_ENDFLAG_IN = '1') then
				transmitNextState <= T_WAITFORFIFO;
			else
				transmitNextState <= T_TRANSMIT;
			end if;
		when T_WAITFORFIFO =>
			bsm_trans <= x"2";
			if (TX_DONE_IN = '1') then --or (TX_DISCFRM_IN = '1') then
				transmitNextState <= T_IDLE;
			else
				transmitNextState <= T_WAITFORFIFO;
			end if;
		when others =>
			bsm_trans <= x"f";
			transmitNextState <= T_IDLE;
	end case;
end process TransmitStateMachine;
	
FifoAvailProc : process (TX_MAC_CLK)
begin
	if rising_edge(TX_MAC_CLK) then
		if (RESET = '1') or (LINK_OK_IN = '0') then -- gk 01.10.10
			tx_fifoavail_i <= '0';
		elsif (transmitCurrentState = T_TRANSMIT) then
			tx_fifoavail_i <= '1';
		else
			tx_fifoavail_i <= '0';
		end if;
	end if;
end process FifoAvailProc;

FifoEmptyProc : process(transmitCurrentState, START_OF_PACKET_IN, TX_EMPTY_IN, RESET)
begin
	if (RESET = '1') or (LINK_OK_IN = '0') then -- gk 01.10.10
		FifoEmpty <= '1';
	elsif    (transmitCurrentState = T_WAITFORFIFO) then
		FifoEmpty <= '1';
	elsif (transmitCurrentState = T_TRANSMIT) then
		FifoEmpty <= TX_EMPTY_IN;
	elsif (((transmitCurrentState = T_IDLE) or (transmitCurrentState = T_WAITFORFIFO)) and (START_OF_PACKET_IN = '1')) then
		FifoEmpty <= '0';
	else
		FifoEmpty <= '1';
	end if;
end process FifoEmptyProc;

tx_fifoeof_i <= '1' when ((DATA_ENDFLAG_IN = '1') and (transmitCurrentState = T_TRANSMIT)) 
					else '0';

--	main MAC state machine
-- MacStateMachineProc : process (CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if RESET = '1' then
-- 			macCurrentState <= M_RESETING;
-- 		else
-- 			macCurrentState <= macNextState;
-- 		end if;
-- 	end if;
-- end process MacStateMachineProc;
-- 	
-- MacStatesMachine: process(macCurrentState, reading_done)
-- begin
-- 	case macCurrentState is
-- 		when M_RESETING =>
-- 			bsm_mac <= x"0";
-- 			macNextState <= M_INIT;
-- 		when M_IDLE =>
-- 			bsm_mac <= x"1";
-- 			macNextState <= M_IDLE;
-- 		when M_INIT =>
-- 			bsm_mac <= x"2";
-- 			if (reading_done = '1') then
-- 				macNextState <= M_IDLE;
-- 			else
-- 				macNextState <= M_INIT;
-- 			end if;
-- 		when others =>
-- 			bsm_mac <= x"f";
-- 			macNextState <= M_RESETING;
-- 	end case;
-- end process MacStatesMachine;	


---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
-- MAC initialization statemachine, memory and address counters
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
	
-- state machine used to initialize MAC registers with data saved in macInitDataInv2.mem via macInitMem
-- MacInitStateMachineProc : process (CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if RESET = '1' then
-- 			macInitState <= I_IDLE;
-- 		else
-- 			macInitState <= macInitNextState;
-- 		end if;
-- 	end if;
-- end process MacInitStateMachineProc;
-- 	
-- MacInitStateMachine : process (macInitState, macCurrentState, init_done, HREADY_IN, reading_done, HDATA_EN_IN, enabled)
-- begin		
-- 	case macInitState is
-- 		when I_IDLE =>		
-- 			bsm_init <= x"0";
-- 			if (macCurrentState = M_INIT) then
-- 				macInitNextState <= I_WRITE;
-- 			else
-- 				macInitNextState <= I_IDLE;
-- 			end if;
-- 		when I_INCRADDRESS =>	
-- 			bsm_init <= x"1";
-- 			if    ((init_done = '0') and (enabled = '0') and (reading_done = '0')) then  -- write to regs 2 and up
-- 				macInitNextState <= I_PAUSE;
-- 			elsif ((init_done = '1') and (enabled = '0') and (reading_done = '0')) then  -- write to regs 0 and 1
-- 				macInitNextState <= I_PAUSE3;
-- 			elsif ((init_done = '1') and (enabled = '1') and (reading_done = '0')) then -- read all regs to fifo
-- 				macInitNextState <= I_PAUSE2;
-- 			else
-- 				macInitNextState <= I_ENDED;
-- 			end if;
-- 		when I_PAUSE =>
-- 			bsm_init <= x"2";
-- 			if (HREADY_IN = '1') then
-- 				macInitNextState <= I_WRITE; 
-- 			else
-- 				macInitNextState <= I_PAUSE;
-- 			end if;
-- 		when I_WRITE =>
-- 			bsm_init <= x"3";
-- 			if (HREADY_IN = '0') then
-- 				macInitNextState <= I_INCRADDRESS;
-- 			else
-- 				macInitNextState <= I_WRITE;
-- 			end if;	
-- 		when I_PAUSE2 =>
-- 			bsm_init <= x"4";
-- 			if (HREADY_IN = '1') then
-- 				macInitNextState <= I_READ;
-- 			else
-- 				macInitNextState <= I_PAUSE2;
-- 			end if;
-- 		when I_READ =>
-- 			bsm_init <= x"5";
-- 			if (HDATA_EN_IN = '0') then
-- 				macInitNextState <= I_INCRADDRESS;
-- 			else
-- 				macInitNextState <= I_READ;
-- 			end if;
-- 		when I_PAUSE3 =>
-- 			bsm_init <= x"6";
-- 			if (HREADY_IN = '1') then
-- 				macInitNextState <= I_WRITE;
-- 			else
-- 				macInitNextState <= I_PAUSE3;
-- 			end if;
-- 		when I_ENDED =>
-- 			bsm_init <= x"7";
-- 			macInitNextState <= I_ENDED;
-- 		when others =>
-- 			bsm_init <= x"f";
-- 			macInitNextState <= I_IDLE;
-- 	end case;
-- end process MacInitStateMachine;
-- 	
-- addrSig <= addr2 when ((reading_done = '0') and (init_done = '1') and (enabled = '1')) 
-- 				 else macInitMemAddr;
-- 
-- -- initialization ROM
-- MacInitMemory : mac_init_mem
-- port map (
-- 	Address		=>	macInitMemAddr,
-- 	OutClock	=>	CLK,
-- 	OutClockEn	=>	macInitMemEn,
-- 	Reset		=>	RESET,
-- 	Q			=>	macInitMemQ	
-- );
-- 	
-- -- MAC ready signal (?)
-- enabledProc : process (CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if    (RESET = '1') then
-- 			enabled <= '0';
-- 		elsif ((reading_done = '0') and (init_done = '1') and (macInitMemAddr = "000010")) then  -- write only to the first register (mode)
-- 			enabled <= '1';
-- 		elsif (macInitState = I_IDLE) then
-- 			enabled <= '0';
-- 		end if;
-- 	end if;
-- end process enabledProc;
-- 	
-- add2 : process (CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if    (RESET = '1') then
-- 			addr2 <= "111111";
-- 		elsif ((macInitState = I_INCRADDRESS) and (init_done = '1') and (enabled = '1')) then
-- 			addr2 <= addr2 + "1";
-- 		elsif (macInitState = I_IDLE) then
-- 			addr2 <= "111111";
-- 		end if;
-- 	end if;
-- end process add2;
-- 	
-- readingDoneProc : process (CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if    (RESET = '1') then
-- 			reading_done <= '0';
-- 		elsif (macInitState = I_IDLE) then
-- 			reading_done <= '0';
-- 		elsif (addr2 = "110101") then  -- read all registers
-- 			reading_done <= '1';
-- 		end if;
-- 	end if;
-- end process readingDoneProc;
-- 
-- initDoneProc : process (CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if    (RESET = '1') then
-- 			init_done <= '0';
-- 		elsif (macInitState = I_IDLE) then
-- 			init_done <= '0';
-- 		elsif (macInitMemAddr = "110101") then -- write to all registers
-- 			init_done <= '1';
-- 		end if;
-- 	end if;
-- end process initDoneProc;
-- 	
-- -- HWRITE signal (registered)
-- hwriteProc : process (CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if    (RESET = '1') then
-- 			hwrite_n_i <= '1';
-- 		elsif ((macInitState = I_WRITE) and (HREADY_IN = '1')) then
-- 			hwrite_n_i <= '0';
-- 		else
-- 			hwrite_n_i <= '1';
-- 		end if;
-- 	end if;
-- end process hwriteProc;
-- 	
-- -- HREAD signal (registered)
-- hreadProc : process (CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if    (RESET = '1') then
-- 			hread_n_i <= '1';
-- 		elsif ((macInitState = I_READ) and (HREADY_IN = '1')) then
-- 			hread_n_i <= '0';
-- 		else
-- 			hread_n_i <= '1';
-- 		end if;
-- 	end if;			
-- end process hreadProc;
-- 	
-- -- HCS signal (registered)
-- hcsProc : process (CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if    (RESET = '1') then
-- 			hcs_n_i <= '1';
-- 		elsif ((macInitState = I_WRITE) and (HREADY_IN = '1')) then
-- 			hcs_n_i <= '0';
-- 		elsif ((macInitState = I_READ) and (HREADY_IN = '1')) then
-- 			hcs_n_i <= '0';
-- 		else
-- 			hcs_n_i <= '1';
-- 		end if;
-- 	end if;
-- end process hcsProc;
-- 	
-- -- address lines for the initialization memory
-- macInitMemAddrProc : process (CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if    (RESET = '1') then
-- 			macInitMemAddr <= "000010";
-- 		elsif (resetAddr = '1') then
-- 			macInitMemAddr <= "000000";
-- 		else
-- 			if    (macInitState = I_INCRADDRESS) then
-- 				macInitMemAddr <= macInitMemAddr + "1";
-- 			elsif (macInitState = I_IDLE) then
-- 				macInitMemAddr <= "000010";
-- 			end if;
-- 		end if;
-- 	end if;
-- end process macInitMemAddrProc;
-- 
-- -- address counter reset signal (registered)
-- resetAddrProc : process (CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if    (RESET = '1') then
-- 			resetAddr <= '0';
-- 		elsif (macInitState = I_IDLE) then
-- 			resetAddr <= '0';
-- 		elsif (macInitMemAddr = "110101") then
-- 			resetAddr <= '1';
-- 		elsif (macInitState = I_PAUSE3) then
-- 			resetAddr <= '0';
-- 		end if;
-- 	end if;
-- end process resetAddrProc;
-- 	
-- macInitMemEn <= '1' when (macCurrentState = M_INIT) 
-- 					else '0';
-- 
-- 
-- 
-- -- Outputs
-- HADDR_OUT          <= b"00" & addrSig;
-- HDATA_OUT          <= macInitMemQ;
-- HCS_OUT            <= hcs_n_i;
-- HWRITE_OUT         <= hwrite_n_i;
-- HREAD_OUT          <= hread_n_i;
TX_FIFOAVAIL_OUT   <= tx_fifoavail_i;
TX_FIFOEOF_OUT     <= tx_fifoeof_i;
TX_FIFOEMPTY_OUT   <= FifoEmpty;

BSM_INIT_OUT       <= bsm_init;
BSM_MAC_OUT        <= bsm_mac;
BSM_TRANS_OUT      <= bsm_trans;
DBG_RD_DONE_OUT    <= reading_done;
DBG_INIT_DONE_OUT  <= init_done;
DBG_ENABLED_OUT    <= enabled;
DEBUG_OUT          <= debug;

end trb_net16_gbe_frame_trans;


--MAC : tsmac3
--port map(
--	--------------------------------------------------------------------------
--	--------------- clock, reset, clock enable -------------------------------
--	hclk				=>	CLK,					-- (in) host clock (100MHz)
--	txmac_clk			=>	TX_MAC_CLK,				-- (in) GbE clock (125MHz)
--	rxmac_clk			=>	'0',					-- (in) not used (no receiving on GbE)
--	reset_n				=>	GSR_N,					-- (in) global set/reset
--	txmac_clk_en		=>	TSM_TX_CLK_EN_IN,		-- (in) from SGMII core, '1' for 1GbE operation
--	rxmac_clk_en		=>	TSM_RX_CLK_EN_IN,		-- (in) from SGMII core, '1' for 1GbE operation
--	--------------------------------------------------------------------------
--	--------------- SGMII receive interface ----------------------------------
--	rxd					=>	x"00",					-- (in) receive data from SGMII core
--	rx_dv 				=>	'0',					-- (in) data valid from SGMII core
--	rx_er				=>	'0',					-- (in) receive data error 
--	col					=>	TSM_COL_IN,				-- (in) collision from SGMII core
--	crs					=>	TSM_CRS_IN,				-- (in) carrier sense from SGMII core
--	--------------------------------------------------------------------------
--	--------------- SGMII transmit interface ---------------------------------
--	txd					=>	CH_TXD_OUT,				-- (out) transmit data to SGMII core
--	tx_en				=>	CH_TX_EN_OUT,			-- (out) transmit enable
--	tx_er				=>	CH_TX_ER_OUT,			-- (out) transmit error
--	--------------------------------------------------------------------------
--	--------------- CPU configuration interface ------------------------------
--	haddr				=>	haddr,					-- (in) host address bus for configuration
--	hdatain				=>	hdataout,				-- (in) host data bus for write accesses
--	hcs_n				=>	hcs,					-- (in) host chip select signal
--	hwrite_n			=>	hwrite,					-- (in) host write strobe signal
--	hread_n				=>	hread,					-- (in) host read strobe signal
--	hdataout			=>	hdatain,				-- (out) host data bus for read accesses
--	hdataout_en_n		=>	hdataout_en,			-- (out) read data valid signal
--	hready_n			=>	hready,					-- (out) data acknowledge signal 
--	cpu_if_gbit_en		=>	open,					-- (out) status bit 
--	--------------------------------------------------------------------------
--	--------------- Transmit FIFO interface ----------------------------------
--	tx_fifodata			=>	ft_data(7 downto 0),	-- (in) transmit FIFO data bus
--	tx_fifoavail		=>	mac_fifoavail,			-- (in) transmit FIFO data available
--	tx_fifoeof			=>	mac_fifoeof,			-- (in) transmit FIFO end of frame 
--	tx_fifoempty		=>	mac_fifoempty,			-- (in) transmit FIFO empty
--	tx_macread			=>	mac_tx_rd_en,			-- (out) transmit FIFO read
--	tx_done				=>	mac_tx_done,			-- (out) transmit done (without errors)
--	tx_sndpaustim		=>	x"0000",				-- (in) PAUSE frame timer
--	tx_sndpausreq		=>	'0',					-- (in) PAUSE frame request
--	tx_fifoctrl			=>	'0',					-- (in) FIFO control frame ('0' = data, '1' = control)
--	tx_discfrm			=>	open,					-- (out) discard frame
--	tx_staten			=>	open,					-- (out) transmit statistics vector enable 
--	tx_statvec			=>	open,					-- (out) transmit statistics vector
--	--------------------------------------------------------------------------
--	--------------- Receive FIFO interface -----------------------------------
--	rx_dbout			=>	open,					-- (out) receive FIFO data output
--	rx_fifo_full		=>	'0',					-- (in) receive FIFO full
--	ignore_pkt			=> 	'0',					-- (in) ignore next packet
--	rx_fifo_error		=>	open,					-- (out) receive FIFO error
--	rx_stat_vector		=>	open,					-- (out) receive statistics vector
--	rx_stat_en			=>	open,					-- (out) receive statistics vector enable
--	rx_write			=>	open,					-- (out) receive FIFO write
--	rx_eof				=>	open,					-- (out) end of frame
--	rx_error			=>	open					-- (out) receive packet error
--);






--MAC : tsmac3
--port map(
----------------- clock and reset port declarations ------------------
--	hclk				=>	LVDS_CLK_200P,
--	txmac_clk			=>	TX_MAC_CLK,
--	rxmac_clk			=>	'0',
--	reset_n				=>	GSR_N, -- done
--	txmac_clk_en		=>	TSM_TX_CLK_EN_IN, -- done
--	rxmac_clk_en		=>	TSM_RX_CLK_EN_IN, -- done
--------------------- Input signals to the GMII ----------------  NOT USED
--	rxd					=>	x"00",
--	rx_dv 				=>	'0',
--	rx_er				=>	'0',
--	col					=>	TSM_COL_IN, -- done
--	crs					=>	TSM_CRS_IN, -- done
--	-------------------- Input signals to the CPU I/F -------------------
--	haddr(5 downto 0)	=>	addrSig, -- done
--	haddr(7 downto 6)	=>	"00",
--	hdatain				=>	macInitMemQ, -- done
--	hcs_n				=>	hcs_n_i, -- done
--	hwrite_n			=>	hwrite_n_i, -- done
--	hread_n				=>	hread_n_i, -- done
------------------ Input signals to the Tx MAC FIFO I/F ---------------
--	tx_fifodata			=>	DATA_IN(7 downto 0), -- done
--	tx_fifoavail		=>	tx_fifoavail_i, -- done
--	tx_fifoeof			=>	tx_fifoeof_i, -- done
--	tx_fifoempty		=>	FifoEmpty, -- done
--	tx_sndpaustim		=>	x"0000",
--	tx_sndpausreq		=>	'0',
--	tx_fifoctrl			=>	'0',  -- always data frame
------------------ Input signals to the Rx MAC FIFO I/F --------------- 
--	rx_fifo_full		=>	'0',
--	ignore_pkt			=> 	'0',
---------------------- Output signals from the GMII -----------------------
--	txd					=>	CH_TXD_OUT, -- done
--	tx_en				=>	CH_TX_EN_OUT, -- done
--	tx_er				=>	CH_TX_ER_OUT, -- done
---------------------- Output signals from the CPU I/F -------------------
--	hdataout			=>	hdataout_i, -- done
--	hdataout_en_n		=>	hdataout_en_n_i, -- done
--	hready_n			=>	hready_n_i, -- done
--	cpu_if_gbit_en		=>	gbe_enabled, -- done
------------------ Output signals from the Tx MAC FIFO I/F --------------- 
--	tx_macread			=>	FifoRd, -- done
--	tx_discfrm			=>	tx_discfrm_i, -- not used
--	tx_staten			=>	tx_staten_i, -- done
--	tx_statvec			=>	tx_statvec_i, -- done
--	tx_done				=>	tx_done_i, -- done
------------------ Output signals from the Rx MAC FIFO I/F ---------------   
--	rx_fifo_error		=>	open,
--	rx_stat_vector		=>	open,
--	rx_dbout			=>	open,
--	rx_write			=>	open,
--	rx_stat_en			=>	open,
--	rx_eof				=>	rx_eof_i, -- done
--	rx_error			=>	rx_error_i -- done
--);
