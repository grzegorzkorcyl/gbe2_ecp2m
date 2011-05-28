LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;
use work.trb_net16_hub_func.all;

use work.trb_net_gbe_components.all;

--********
-- creates a reply for an incoming ARP request

entity trb_net16_gbe_response_constructor_ARP is
port (
	CLK			: in	std_logic;  -- system clock
	RESET			: in	std_logic;
	
-- INTERFACE	
	PS_DATA_IN		: in	std_logic_vector(8 downto 0);
	PS_WR_EN_IN		: in	std_logic;
	PS_ACTIVATE_IN		: in	std_logic;
	PS_RESPONSE_READY_OUT	: out	std_logic;
	PS_BUSY_OUT		: out	std_logic;
	PS_SELECTED_IN		: in	std_logic;
	PS_SRC_MAC_ADDRESS_IN	: in	std_logic_vector(47 downto 0);
		
	TC_RD_EN_IN		: in	std_logic;
	TC_DATA_OUT		: out	std_logic_vector(8 downto 0);
	TC_FRAME_SIZE_OUT	: out	std_logic_vector(15 downto 0);
	TC_FRAME_TYPE_OUT	: out	std_logic_vector(15 downto 0);
	
	TC_DEST_MAC_OUT		: out	std_logic_vector(47 downto 0);
	TC_DEST_IP_OUT		: out	std_logic_vector(31 downto 0);
	TC_DEST_UDP_OUT		: out	std_logic_vector(15 downto 0);
	TC_SRC_MAC_OUT		: out	std_logic_vector(47 downto 0);
	TC_SRC_IP_OUT		: out	std_logic_vector(31 downto 0);
	TC_SRC_UDP_OUT		: out	std_logic_vector(15 downto 0);
	
	TC_BUSY_IN		: in	std_logic;
	
	RECEIVED_FRAMES_OUT	: out	std_logic_vector(15 downto 0);
	SENT_FRAMES_OUT		: out	std_logic_vector(15 downto 0);
-- END OF INTERFACE

-- debug
	DEBUG_OUT		: out	std_logic_vector(31 downto 0)
);
end trb_net16_gbe_response_constructor_ARP;


architecture trb_net16_gbe_response_constructor_ARP of trb_net16_gbe_response_constructor_ARP is

attribute syn_encoding	: string;

type dissect_states is (IDLE, SAVE_HEADERS, SAVE_OPCODE, SAVE_SRC_MAC, SAVE_SRC_IP, REACH_END, 
			WAIT_FOR_LOAD, LOAD_HEADERS, LOAD_OPCODE, LOAD_MY_MAC, LOAD_MY_IP,
			LOAD_TRG_MAC, LOAD_TRG_IP, CLEANUP);
signal dissect_current_state, dissect_next_state : dissect_states;
attribute syn_encoding of dissect_current_state: signal is "safe,gray";

signal saved_headers            : std_logic_vector(47 downto 0);
signal saved_opcode             : std_logic_vector(15 downto 0);
signal saved_src_mac            : std_logic_vector(47 downto 0);
signal saved_src_ip             : std_logic_vector(31 downto 0);
signal data_ctr                 : std_logic_vector(4 downto 0);
signal saving_data              : std_logic;

signal state                    : std_logic_vector(3 downto 0);
signal rec_frames               : std_logic_vector(15 downto 0);
signal sent_frames              : std_logic_vector(15 downto 0);

begin

DISSECT_MACHINE_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			dissect_current_state <= IDLE;
		else
			dissect_current_state <= dissect_next_state;
		end if;
	end if;
end process DISSECT_MACHINE_PROC;

DISSECT_MACHINE : process(dissect_current_state, PS_WR_EN_IN, PS_ACTIVATE_IN, PS_DATA_IN, TC_BUSY_IN, data_ctr)
begin
	case dissect_current_state is
	
		when IDLE =>
			state <= x"1";
			if (PS_WR_EN_IN = '1' and PS_ACTIVATE_IN = '1') then
				dissect_next_state <= SAVE_HEADERS;
			else
				dissect_next_state <= IDLE;
			end if;
		
		when SAVE_HEADERS =>
			state <= x"2";
			if (data_ctr = "00101") then
				dissect_next_state <= SAVE_OPCODE;
			else
				dissect_next_state <= SAVE_HEADERS;
			end if;
			
		when SAVE_OPCODE =>
			state <= x"3";
			if (data_ctr = "00111") then
				dissect_next_state <= SAVE_SRC_MAC;
			else
				dissect_next_state <= SAVE_OPCODE;
			end if;
			
		when SAVE_SRC_MAC =>
			state <= x"4";
			if (data_ctr = "01101") then
				dissect_next_state <= SAVE_SRC_IP;
			else
				dissect_next_state <= SAVE_SRC_MAC;
			end if;
		
		when SAVE_SRC_IP =>
			state <= x"5";
			if (data_ctr = "10001") then
				dissect_next_state <= REACH_END;
			else
				dissect_next_state <= SAVE_SRC_IP;
			end if;
		
		when REACH_END =>
			state <= x"6";
			if (PS_DATA_IN(8) = '1') then
				dissect_next_state <= WAIT_FOR_LOAD;
			else
				dissect_next_state <= REACH_END;
			end if;
			
		when WAIT_FOR_LOAD =>
			state <= x"7";
			if (TC_BUSY_IN = '0') then
				dissect_next_state <= LOAD_HEADERS;
			else
				dissect_next_state <= WAIT_FOR_LOAD;
			end if;
		
		when LOAD_HEADERS =>
			state <= x"8";
			if (data_ctr = "00101") then
				dissect_next_state <= LOAD_OPCODE;
			else
				dissect_next_state <= LOAD_HEADERS;
			end if;
			
		when LOAD_OPCODE =>
			state <= x"9";
			if (data_ctr = "00111") then
				dissect_next_state <= LOAD_MY_MAC;
			else
				dissect_next_state <= LOAD_OPCODE;
			end if;
		
		when LOAD_MY_MAC =>
			state <= x"a";
			if (data_ctr = "01101") then
				dissect_next_state <= LOAD_MY_IP;
			else
				dissect_next_state <= LOAD_MY_MAC;
			end if;
		
		when LOAD_MY_IP =>
			state <= x"b";
			if (data_ctr = "10001") then
				dissect_next_state <= LOAD_TRG_MAC;
			else
				dissect_next_state <= LOAD_MY_IP;
			end if;
		
		when LOAD_TRG_MAC =>
			state <= x"c";
			if (data_ctr = "10111") then
				dissect_next_state <= LOAD_TRG_IP;
			else
				dissect_next_state <= LOAD_TRG_MAC;
			end if;
		
		when LOAD_TRG_IP =>
			state <= x"d";
			if (data_ctr = "11011") then
				dissect_next_state <= CLEANUP;
			else
				dissect_next_state <= LOAD_TRG_IP;
			end if;
		
		when CLEANUP =>
			state <= x"e";
			dissect_next_state <= IDLE;
	
	end case;
end process DISSECT_MACHINE;

-- flag to mark the saving or loading process
SAVING_DATA_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (dissect_current_state = IDLE) then
			saving_data <= '1';
		elsif (dissect_current_state = WAIT_FOR_LOAD) then
			saving_data <= '0';
		end if;	
	end if;		
end process;

DATA_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (dissect_current_state = CLEANUP) or (dissect_current_state = WAIT_FOR_LOAD) then
			data_ctr <= (others => '0');
		elsif (PS_WR_EN_IN = '1') and (PS_ACTIVATE_IN = '1') and (saving_data = '1') then  -- in case of saving data from incoming frame
			data_ctr <= data_ctr + x"1";
		elsif (TC_RD_EN_IN = '1') and (saving_data = '0') and (PS_SELECTED_IN = '1') then  -- in case of constructing response
			data_ctr <= data_ctr + x"1";
		end if;
	end if;
end process DATA_CTR_PROC;

-- process that saves headers and sender addresses from the frame into registers
STORE_DATA_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (dissect_current_state = CLEANUP) then
			saved_headers <= (others => '0');
			saved_src_ip  <= (others => '0');
			saved_src_mac <= (others => '0');
			
		elsif (saving_data = '1') and (dissect_current_state /= WAIT_FOR_LOAD) then  -- saving data from incoming request
		
			case (data_ctr) is
				-- headers
				when "00000" =>
					saved_headers(7 downto 0) <= PS_DATA_IN(7 downto 0);
				when "00001" =>
					saved_headers(15 downto 8) <= PS_DATA_IN(7 downto 0);
				when "00010" =>
					saved_headers(23 downto 16) <= PS_DATA_IN(7 downto 0);
				when "00011" =>
					saved_headers(31 downto 24) <= PS_DATA_IN(7 downto 0);
				when "00100" =>
					saved_headers(39 downto 32) <= PS_DATA_IN(7 downto 0);
				when "00101" =>
					saved_headers(47 downto 40) <= PS_DATA_IN(7 downto 0);
				-- opcode
				when "00110" =>
					saved_opcode(7 downto 0) <= PS_DATA_IN(7 downto 0);
				when "00111" =>
					saved_opcode(15 downto 8) <= PS_DATA_IN(7 downto 0);
				-- sender mac
				when "01000" =>
					saved_src_mac(7 downto 0) <= PS_DATA_IN(7 downto 0);
				when "01001" =>
					saved_src_mac(15 downto 8) <= PS_DATA_IN(7 downto 0);
				when "01010" =>
					saved_src_mac(23 downto 16) <= PS_DATA_IN(7 downto 0);
				when "01011" =>
					saved_src_mac(31 downto 24) <= PS_DATA_IN(7 downto 0);
				when "01100" =>
					saved_src_mac(39 downto 32) <= PS_DATA_IN(7 downto 0);
				when "01101" =>
					saved_src_mac(47 downto 40) <= PS_DATA_IN(7 downto 0);
				-- sender ip
				when "01110" =>
					saved_src_ip(7 downto 0) <= PS_DATA_IN(7 downto 0);
				when "01111" =>
					saved_src_ip(15 downto 8) <= PS_DATA_IN(7 downto 0);
				when "10000" =>
					saved_src_ip(23 downto 16) <= PS_DATA_IN(7 downto 0);
				when "10001" =>
					saved_src_ip(31 downto 24) <= PS_DATA_IN(7 downto 0);
				when others => null;
			end case;
			
		else  -- loading reply data into constructor
		
			TC_DATA_OUT(8) <= '0';
		
			case (data_ctr) is
				-- headers
				when "00000" =>
					TC_DATA_OUT(7 downto 0) <= saved_headers(7 downto 0);
				when "00001" =>
					TC_DATA_OUT(7 downto 0) <= saved_headers(15 downto 8);
				when "00010" =>
					TC_DATA_OUT(7 downto 0) <= saved_headers(23 downto 16);
				when "00011" =>
					TC_DATA_OUT(7 downto 0) <= saved_headers(31 downto 24);
				when "00100" =>
					TC_DATA_OUT(7 downto 0) <= saved_headers(39 downto 32);
				when "00101" =>
					TC_DATA_OUT(7 downto 0) <= saved_headers(47 downto 40);
				-- opcode
				when "00110" =>
					TC_DATA_OUT(7 downto 0) <= x"00";
				when "00111" =>
					TC_DATA_OUT(7 downto 0) <= x"02";
				-- sender mac (my)
				when "01000" =>
					TC_DATA_OUT(7 downto 0) <= x"00";
				when "01001" =>
					TC_DATA_OUT(7 downto 0) <= x"11";
				when "01010" =>
					TC_DATA_OUT(7 downto 0) <= x"22";
				when "01011" =>
					TC_DATA_OUT(7 downto 0) <= x"33";
				when "01100" =>
					TC_DATA_OUT(7 downto 0) <= x"44";
				when "01101" =>
					TC_DATA_OUT(7 downto 0) <= x"55";
				-- sender ip (my)
				when "01110" =>
					TC_DATA_OUT(7 downto 0) <= x"c0";
				when "01111" =>
					TC_DATA_OUT(7 downto 0) <= x"a9";
				when "10000" =>
					TC_DATA_OUT(7 downto 0) <= x"00";
				when "10001" =>
					TC_DATA_OUT(7 downto 0) <= x"02";
				-- target mac
				when "10010" =>
					TC_DATA_OUT(7 downto 0) <= saved_src_mac(7 downto 0);
				when "10011" =>
					TC_DATA_OUT(7 downto 0) <= saved_src_mac(15 downto 8);
				when "10100" =>
					TC_DATA_OUT(7 downto 0) <= saved_src_mac(23 downto 16);
				when "10101" =>
					TC_DATA_OUT(7 downto 0) <= saved_src_mac(31 downto 24);
				when "10110" =>
					TC_DATA_OUT(7 downto 0) <= saved_src_mac(39 downto 32);
				when "10111" =>
					TC_DATA_OUT(7 downto 0) <= saved_src_mac(47 downto 40);
				-- target ip
				when "11000" =>
					TC_DATA_OUT(7 downto 0) <= saved_src_ip(7 downto 0);
				when "11001" =>
					TC_DATA_OUT(7 downto 0) <= saved_src_ip(15 downto 8);
				when "11010" =>
					TC_DATA_OUT(7 downto 0) <= saved_src_ip(23 downto 16);
				when "11011" =>
					TC_DATA_OUT(7 downto 0) <= saved_src_ip(31 downto 24);
					TC_DATA_OUT(8) <= '1';
				when others => null;
			end case;
		
		end if;
	end if;
end process STORE_DATA_PROC;

PS_BUSY_OUT <= '0' when (dissect_current_state = IDLE) else '1';

PS_RESPONSE_READY_OUT <= '1' when (saving_data = '0') else '0';

TC_FRAME_SIZE_OUT <= x"001c";

TC_FRAME_TYPE_OUT <= x"0608";

REC_FRAMES_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			rec_frames <= (others => '0');
		elsif (dissect_current_state = IDLE and PS_WR_EN_IN = '1' and PS_ACTIVATE_IN = '1') then
			rec_frames <= rec_frames + x"1";
		end if;
	end if;
end process REC_FRAMES_PROC;

SENT_FRAMES_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			sent_frames <= (others => '0');
		elsif (dissect_current_state = WAIT_FOR_LOAD and TC_BUSY_IN = '0') then
			sent_frames <= sent_frames + x"1";
		end if;
	end if;
end process SENT_FRAMES_PROC;

RECEIVED_FRAMES_OUT <= rec_frames;
SENT_FRAMES_OUT     <= sent_frames;

-- **** debug
DEBUG_OUT(3 downto 0)   <= state;
DEBUG_OUT(4)            <= '0';
DEBUG_OUT(7 downto 5)   <= "000";
DEBUG_OUT(8)            <= '0';
DEBUG_OUT(11 downto 9)  <= "000";
DEBUG_OUT(31 downto 12) <= (others => '0');
-- ****

end trb_net16_gbe_response_constructor_ARP;


