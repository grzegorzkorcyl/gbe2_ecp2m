LIBRARY ieee;
use ieee.std_logic_1164.all;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;
use IEEE.std_logic_arith.all;

library work;

entity ip_configurator is
port( 
	CLK							: in	std_logic;
	RESET						: in	std_logic;
	-- configuration interface
	START_CONFIG_IN				: in	std_logic; -- start configuration run
	BANK_SELECT_IN				: in	std_logic_vector(3 downto 0); -- selects config bank 
	CONFIG_DONE_OUT				: out	std_logic; -- configuration run ended, new values can be used
	MEM_ADDR_OUT				: out	std_logic_vector(7 downto 0); -- address for
	MEM_DATA_IN					: in	std_logic_vector(31 downto 0); -- data from IP memory
	MEM_CLK_OUT					: out	std_logic; -- clock for BlockRAM
	-- information for IP cores
	DEST_MAC_OUT				: out	std_logic_vector(47 downto 0); -- destination MAC address
	DEST_IP_OUT					: out	std_logic_vector(31 downto 0); -- destination IP address
	DEST_UDP_OUT				: out	std_logic_vector(15 downto 0); -- destination port
	SRC_MAC_OUT					: out	std_logic_vector(47 downto 0); -- source MAC address
	SRC_IP_OUT					: out	std_logic_vector(31 downto 0); -- source IP address
	SRC_UDP_OUT					: out	std_logic_vector(15 downto 0); -- source port
	MTU_OUT						: out	std_logic_vector(15 downto 0); -- MTU size (max frame size)
	-- Debug
	DEBUG_OUT					: out	std_logic_vector(31 downto 0)
);
end entity;

architecture ip_configurator of ip_configurator is

-- -- Placer Directives
-- attribute HGROUP : string;
-- -- for whole architecture
-- attribute HGROUP of ip_configurator : architecture  is "GBE_conf_group";

type STATES	is (IDLE, LOAD_REG, DELAY0, DELAY1, DELAY2, LOAD_DONE);
signal CURRENT_STATE, NEXT_STATE : STATES;
signal bsm					: std_logic_vector(3 downto 0);
signal ce_ctr_comb			: std_logic;
signal ce_ctr				: std_logic;
signal rst_ctr_comb			: std_logic;
signal rst_ctr				: std_logic;
signal cfg_done_comb		: std_logic;
signal cfg_done				: std_logic;

signal ctr_done_comb		: std_logic;
signal ctr_done				: std_logic;

signal wr_select_comb		: std_logic_vector(15 downto 0);
signal wr_select			: std_logic_vector(15 downto 0);
signal wr_select_q			: std_logic_vector(15 downto 0);

signal addr_ctr				: std_logic_vector(3 downto 0);
signal dest_mac				: std_logic_vector(47 downto 0);
signal dest_ip				: std_logic_vector(31 downto 0);
signal dest_udp				: std_logic_vector(15 downto 0);
signal src_mac				: std_logic_vector(47 downto 0);
signal src_ip				: std_logic_vector(31 downto 0);
signal src_udp				: std_logic_vector(15 downto 0);
signal mtu					: std_logic_vector(15 downto 0);

signal debug				: std_logic_vector(31 downto 0);

begin


-- Statemachine for reading data payload, handling IPU channel and storing data in the SPLIT_FIFO
STATE_MACHINE_PROC: process( CLK )
begin
	if rising_edge(CLK) then
		if RESET = '1' then
			CURRENT_STATE <= IDLE;
			ce_ctr        <= '0';
			rst_ctr       <= '0';
			cfg_done      <= '0';
		else
			CURRENT_STATE <= NEXT_STATE;
			ce_ctr        <= ce_ctr_comb;
			rst_ctr       <= rst_ctr_comb;
			cfg_done      <= cfg_done_comb;
		end if;
	end if;
end process STATE_MACHINE_PROC;

STATE_MACHINE_TRANS: process( CURRENT_STATE, START_CONFIG_IN, ctr_done )
begin
	NEXT_STATE <= IDLE;
	ce_ctr_comb <= '0';
	rst_ctr_comb <= '0';
	cfg_done_comb <= '0';
	case CURRENT_STATE is
		when IDLE =>
			bsm <= x"0";
			if( START_CONFIG_IN = '1' ) then
				NEXT_STATE <= LOAD_REG;
				ce_ctr_comb <= '1';
			else
				NEXT_STATE <= IDLE;
			end if;
		when LOAD_REG =>
			bsm <= x"1";
			if( ctr_done = '1' ) then
				NEXT_STATE <= DELAY0;
				rst_ctr_comb <= '1';
			else
				NEXT_STATE <= LOAD_REG;
				ce_ctr_comb <= '1';
			end if;
		when DELAY0 =>
			bsm <= x"2";
			NEXT_STATE <= DELAY1;
		when DELAY1 =>
			bsm <= x"3";
			NEXT_STATE <= DELAY2;
		when DELAY2 =>
			bsm <= x"4";
			NEXT_STATE <= LOAD_DONE;
			cfg_done_comb <= '1';
		when LOAD_DONE =>
			bsm <= x"2";
			if( START_CONFIG_IN = '0' ) then
				NEXT_STATE <= IDLE;
			else
				NEXT_STATE <= LOAD_DONE;
				cfg_done_comb <= '1';
			end if;
		when others =>
			bsm <= x"f";
			NEXT_STATE <= IDLE;
	end case;
end process STATE_MACHINE_TRANS;

-- address counter
THE_ADDR_CTR_PROC: process( CLK )
begin
	if ( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_ctr = '1') ) then
			addr_ctr <= (others => '0');
		elsif( ce_ctr = '1' ) then
			addr_ctr <= addr_ctr + 1;
		end if;	
	end if;
end process THE_ADDR_CTR_PROC;

ctr_done_comb <= '1' when (addr_ctr = x"e") else '0';

THE_SYNC_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		ctr_done    <= ctr_done_comb;
		wr_select_q <= wr_select;
		wr_select   <= wr_select_comb;
	end if;
end process THE_SYNC_PROC;

-- generate combinatorial write select signals, register and delay the (output registers in EBR!)
wr_select_comb(0)  <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"0") ) else '0'; -- dest MAC low
wr_select_comb(1)  <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"1") ) else '0'; -- dest MAC high
wr_select_comb(2)  <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"2") ) else '0'; -- dest IP 
wr_select_comb(3)  <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"3") ) else '0'; -- dest port
wr_select_comb(4)  <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"4") ) else '0'; -- src MAC low
wr_select_comb(5)  <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"5") ) else '0'; -- src MAC high
wr_select_comb(6)  <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"6") ) else '0'; -- src IP
wr_select_comb(7)  <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"7") ) else '0'; -- src port
wr_select_comb(8)  <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"8") ) else '0'; -- MTU
wr_select_comb(9)  <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"9") ) else '0';
wr_select_comb(10) <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"a") ) else '0';
wr_select_comb(11) <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"b") ) else '0';
wr_select_comb(12) <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"c") ) else '0';
wr_select_comb(13) <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"d") ) else '0';
wr_select_comb(14) <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"e") ) else '0';
wr_select_comb(15) <= '1' when ( (ce_ctr = '1') and (addr_ctr = x"f") ) else '0';

-- destination MAC low register
THE_D_MAC_LOW_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( RESET = '1' ) then
			dest_mac(31 downto 0) <= (others => '0');
		elsif( wr_select_q(0) = '1') then
			dest_mac(31 downto 0) <= mem_data_in;
		end if;
	end if;
end process THE_D_MAC_LOW_PROC;

-- destination MAC high register
THE_D_MAC_HIGH_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( RESET = '1' ) then
			dest_mac(47 downto 32) <= (others => '0');
		elsif( wr_select_q(1) = '1') then
			dest_mac(47 downto 32) <= mem_data_in(15 downto 0);
		end if;
	end if;
end process THE_D_MAC_HIGH_PROC;

-- destination IP register
THE_D_IP_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( RESET = '1' ) then
			dest_ip <= (others => '0');
		elsif( wr_select_q(2) = '1') then
			dest_ip <= mem_data_in;
		end if;
	end if;
end process THE_D_IP_PROC;

-- destination PORT register
THE_D_PORT_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( RESET = '1' ) then
			dest_udp <= (others => '0');
		elsif( wr_select_q(3) = '1') then
			dest_udp <= mem_data_in(15 downto 0);
		end if;
	end if;
end process THE_D_PORT_PROC;

-- source MAC low register
THE_S_MAC_LOW_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( RESET = '1' ) then
			src_mac(31 downto 0) <= (others => '0');
		elsif( wr_select_q(4) = '1') then
			src_mac(31 downto 0) <= mem_data_in;
		end if;
	end if;
end process THE_S_MAC_LOW_PROC;

-- source MAC high register
THE_S_MAC_HIGH_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( RESET = '1' ) then
			src_mac(47 downto 32) <= (others => '0');
		elsif( wr_select_q(5) = '1') then
			src_mac(47 downto 32) <= mem_data_in(15 downto 0);
		end if;
	end if;
end process THE_S_MAC_HIGH_PROC;

-- source IP register
THE_S_IP_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( RESET = '1' ) then
			src_ip <= (others => '0');
		elsif( wr_select_q(6) = '1') then
			src_ip <= mem_data_in;
		end if;
	end if;
end process THE_S_IP_PROC;

-- source PORT register
THE_S_PORT_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( RESET = '1' ) then
			src_udp <= (others => '0');
		elsif( wr_select_q(7) = '1') then
			src_udp <= mem_data_in(15 downto 0);
		end if;
	end if;
end process THE_S_PORT_PROC;

-- MTU size register
THE_MTU_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( RESET = '1' ) then
			mtu <= (others => '0');
		elsif( wr_select_q(8) = '1') then
			mtu <= mem_data_in(15 downto 0);
		end if;
	end if;
end process THE_MTU_PROC;


-- Debug signals
debug(31 downto 12) <= (others => '0');
debug(11 downto 8)  <= addr_ctr;
debug(7)            <= '0';
debug(6)            <= ctr_done;
debug(5)            <= ce_ctr;
debug(4)            <= rst_ctr;
debug(3 downto 0)   <= bsm;
-- Outputs
MEM_ADDR_OUT(7 downto 4) <= BANK_SELECT_IN;
MEM_ADDR_OUT(3 downto 0) <= addr_ctr;
MEM_CLK_OUT              <= CLK;
CONFIG_DONE_OUT          <= cfg_done;

-- destination MAC address - swap for user convinience
DEST_MAC_OUT(47 downto 40) <= dest_mac(7 downto 0);
DEST_MAC_OUT(39 downto 32) <= dest_mac(15 downto 8);
DEST_MAC_OUT(31 downto 24) <= dest_mac(23 downto 16);
DEST_MAC_OUT(23 downto 16) <= dest_mac(31 downto 24);
DEST_MAC_OUT(15 downto 8)  <= dest_mac(39 downto 32);
DEST_MAC_OUT(7 downto 0)   <= dest_mac(47 downto 40);

-- destination IP address - swap for user convinience
DEST_IP_OUT(31 downto 24)  <= dest_ip(7 downto 0);
DEST_IP_OUT(23 downto 16)  <= dest_ip(15 downto 8);
DEST_IP_OUT(15 downto 8)   <= dest_ip(23 downto 16);
DEST_IP_OUT(7 downto 0)    <= dest_ip(31 downto 24);

-- destination port address - swap for user convinience
DEST_UDP_OUT(15 downto 8)  <= dest_udp(7 downto 0);
DEST_UDP_OUT(7 downto 0)   <= dest_udp(15 downto 8);

-- source MAC address - swap for user convinience
SRC_MAC_OUT(47 downto 40)  <= src_mac(7 downto 0);
SRC_MAC_OUT(39 downto 32)  <= src_mac(15 downto 8);
SRC_MAC_OUT(31 downto 24)  <= src_mac(23 downto 16);
SRC_MAC_OUT(23 downto 16)  <= src_mac(31 downto 24);
SRC_MAC_OUT(15 downto 8)   <= src_mac(39 downto 32);
SRC_MAC_OUT(7 downto 0)    <= src_mac(47 downto 40);

-- source IP address - swap for user convinience
SRC_IP_OUT(31 downto 24)   <= src_ip(7 downto 0);
SRC_IP_OUT(23 downto 16)   <= src_ip(15 downto 8);
SRC_IP_OUT(15 downto 8)    <= src_ip(23 downto 16);
SRC_IP_OUT(7 downto 0)     <= src_ip(31 downto 24);

-- source port address - swap for user convinience
SRC_UDP_OUT(15 downto 8)   <= src_udp(7 downto 0);
SRC_UDP_OUT(7 downto 0)    <= src_udp(15 downto 8);

-- DO NOT SWAP!
MTU_OUT                  <= mtu;

DEBUG_OUT  <= debug;

end architecture;