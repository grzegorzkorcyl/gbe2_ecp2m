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
	TX_STAT_EN_IN		: in	std_logic;
	TX_STATVEC_IN		: in	std_logic_vector(30 downto 0);
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

--attribute HGROUP : string;
--attribute HGROUP of trb_net16_gbe_frame_trans : architecture  is "GBE_BUF_group";

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
signal sent_ctr                 : std_logic_vector(31 downto 0);

begin

-- Fakes
debug(63 downto 32) <= (others => '0');
debug(31 downto 0)  <= sent_ctr;


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
					
SENT_CTR_PROC : process(TX_MAC_CLK)
begin
	if rising_edge(TX_MAC_CLK) then
		if (RESET = '1') then
			sent_ctr <= (others => '0');
		elsif (TX_DONE_IN = '1') and (TX_STAT_EN_IN = '1') and (TX_STATVEC_IN(0) = '1')  then
			sent_ctr <= sent_ctr + x"1";
		end if;
	end if;
end process SENT_CTR_PROC;
	

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
