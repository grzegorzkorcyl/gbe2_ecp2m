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
-- 

entity trb_net16_gbe_response_constructor_DHCP is
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
	PS_DEST_MAC_ADDRESS_IN  : in	std_logic_vector(47 downto 0);
	PS_SRC_IP_ADDRESS_IN	: in	std_logic_vector(31 downto 0);
	PS_DEST_IP_ADDRESS_IN	: in	std_logic_vector(31 downto 0);
	PS_SRC_UDP_PORT_IN	: in	std_logic_vector(15 downto 0);
	PS_DEST_UDP_PORT_IN	: in	std_logic_vector(15 downto 0);
		
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
end trb_net16_gbe_response_constructor_DHCP;


architecture trb_net16_gbe_response_constructor_DHCP of trb_net16_gbe_response_constructor_DHCP is

attribute syn_encoding	: string;

type main_states is (BOOTING, SENDING_DISCOVER, WAITING_FOR_OFFER, SENDING_REQUEST, WAITING_FOR_ACK, ESTABLISHED);
signal main_current_state, main_next_state : main_states;
attribute syn_encoding of main_current_state: signal is "safe,gray";

type receive_states is (IDLE, DISCARD, CLEANUP, SAVE_VALUES);
signal receive_current_state, receive_next_state : receive_states;
attribute syn_encoding of receive_current_state: signal is "safe,gray";

type discover_states is (IDLE, BOOTP_HEADERS, CLIENT_IP, YOUR_IP, ZEROS1, MY_MAC, ZEROS2, VENDOR_VALS, CLEANUP);
signal construct_current_state, construct_next_state : discover_states;
attribute syn_encoding of construct_current_state: signal is "safe,gray";

signal state                    : std_logic_vector(3 downto 0);
signal rec_frames               : std_logic_vector(15 downto 0);
signal sent_frames              : std_logic_vector(15 downto 0);

signal wait_ctr                 : std_logic_vector(31 downto 0);  -- wait for 5 sec before sending request
signal load_ctr                 : integer range 0 to 600 := 0;

signal bootp_hdr                : std_logic_vector(95 downto 0);
signal my_mac_addr              : std_logic_vector(47 downto 0);  -- only temporary

signal tc_data                  : std_logic_vector(8 downto 0);
signal vendor_values            : std_logic_vector(183 downto 0);
signal discard_incoming         : std_logic;
signal save_ctr                 : integer range 0 to 600 := 0;
signal saved_transaction_id     : std_logic_vector(31 downto 0);
signal saved_proposed_ip        : std_logic_vector(31 downto 0);
signal saved_dhcp_type          : std_logic_vector(23 downto 0);
signal saved_true_ip            : std_logic_vector(31 downto 0);
signal transaction_id           : std_logic_vector(31 downto 0);
signal client_ip_reg            : std_logic_vector(31 downto 0);
signal your_ip_reg              : std_logic_vector(31 downto 0);

begin


-- ****
-- fixing the constant values for DHCP request headers
TC_DEST_MAC_OUT <= x"ffffffffffff";
TC_DEST_IP_OUT  <= x"ffffffff";
TC_DEST_UDP_OUT <= x"4300";
TC_SRC_MAC_OUT  <= my_mac_addr;
TC_SRC_IP_OUT   <= x"00000000";
TC_SRC_UDP_OUT  <= x"4400";
bootp_hdr(7 downto 0)   <= x"01";  -- message type(request)
bootp_hdr(15 downto 8)  <= x"01";  -- hardware type (eth)
bootp_hdr(23 downto 16) <= x"06";  -- hardware address length
bootp_hdr(31 downto 24) <= x"00";  -- hops
bootp_hdr(63 downto 32) <= transaction_id;  -- transaction id;
bootp_hdr(95 downto 64) <= x"0000_0000";  -- seconds elapsed/flags
transaction_id <= x"cefa_adde";
my_mac_addr <= x"efbeefbe0000";  -- my mac address later
vendor_values(31 downto 0)    <= x"63538263"; -- magic cookie (dhcp message)
vendor_values(55 downto 32)   <= x"010135"; -- dhcp discover
vendor_values(79 downto 56)   <= x"01073d"; -- client identifier
vendor_values(127 downto 80)  <= my_mac_addr;  -- client identifier
vendor_values(143 downto 128) <= x"040c";  -- client name
vendor_values(175 downto 144) <= x"33435254";  -- client name (TRB3)
vendor_values(183 downto 176) <= x"ff"; -- vendor values termination


MAIN_MACHINE_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			main_current_state <= BOOTING;
		else
			main_current_state <= main_next_state;
		end if;
	end if;
end process MAIN_MACHINE_PROC;

MAIN_MACHINE : process(main_current_state, construct_current_state, wait_ctr, receive_current_state, PS_DATA_IN)
begin

	case (main_current_state) is
	
		when BOOTING =>
			if (wait_ctr = x"3b9a_ca00") then  -- wait for 10 sec
			--if (wait_ctr = x"0000_0010") then
				main_next_state <= SENDING_DISCOVER;
			else
				main_next_state <= BOOTING;
			end if;
		
		when SENDING_DISCOVER =>
			if (construct_current_state = CLEANUP) then
				main_next_state <= WAITING_FOR_OFFER;
			else
				main_next_state <= SENDING_DISCOVER;
			end if;
		
		when WAITING_FOR_OFFER =>
			if (receive_current_state = SAVE_VALUES) and (PS_DATA_IN(8) = '1') then
				main_next_state <= SENDING_REQUEST;
			else
				main_next_state <= WAITING_FOR_OFFER;
			end if;
		
		when SENDING_REQUEST =>
			if (construct_current_state = CLEANUP) then
				main_next_state <= WAITING_FOR_ACK;
			else
				main_next_state <= SENDING_REQUEST;
			end if;
		
		when WAITING_FOR_ACK =>
			if (receive_current_state = SAVE_VALUES) and (PS_DATA_IN(8) = '1') then
				main_next_state <= ESTABLISHED;
			else
				main_next_state <= WAITING_FOR_ACK;
			end if;
		
		when ESTABLISHED =>
			main_next_state <= ESTABLISHED;
	
	end case;

end process MAIN_MACHINE;

WAIT_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			wait_ctr <= (others => '0');
		elsif (main_current_state = BOOTING) then
			wait_ctr <= wait_ctr + x"1";
		end if;
	end if;
end process WAIT_CTR_PROC;

discard_incoming <= '0' when (main_current_state = WAITING_FOR_OFFER or main_current_state = WAITING_FOR_ACK) else '0';

RECEIVE_MACHINE_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			receive_current_state <= IDLE;
		else
			receive_current_state <= receive_next_state;
		end if;
	end if;
end process RECEIVE_MACHINE_PROC;

RECEIVE_MACHINE : process(receive_current_state, main_current_state, PS_DATA_IN, PS_DEST_MAC_ADDRESS_IN, my_mac_addr, PS_ACTIVATE_IN, discard_incoming, save_ctr)
begin
	case receive_current_state is
	
		when IDLE =>
			if (PS_ACTIVATE_IN = '1') then
				if (discard_incoming = '0') then  -- ready to receive dhcp frame
					if (PS_DEST_MAC_ADDRESS_IN = my_mac_addr) then  -- check if i'm the addressee (discards broadcasts also)
						receive_next_state <= SAVE_VALUES;
					else
						receive_next_state <= DISCARD;  -- discard if the frame is not for me
					end if;
				else
					receive_next_state <= DISCARD;
				end if;
			else
				receive_next_state <= IDLE;
			end if;
			
		when SAVE_VALUES =>
			if (PS_DATA_IN(8) = '1') then
				receive_next_state <= CLEANUP;
			elsif (save_ctr = 9) and (saved_transaction_id /= bootp_hdr(63 downto 32)) then  -- check if the same transaction
				receive_next_state <= DISCARD;
			-- if wrong message at the wrong time
			elsif (main_current_state = WAITING_FOR_OFFER) and (save_ctr = 244) and (saved_dhcp_type /= x"020135") then
				receive_next_state <= DISCARD;			
			else
				receive_next_state <= SAVE_VALUES;
			end if;
		
		when DISCARD =>
			if (PS_DATA_IN(8) = '1') then
				receive_next_state <= CLEANUP;
			else
				receive_next_state <= DISCARD;
			end if;
			
		when CLEANUP =>
			receive_next_state <= IDLE;
	
	end case;

end process RECEIVE_MACHINE;

SAVE_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (receive_current_state = IDLE) then
			save_ctr <= 0;
		elsif (receive_current_state = SAVE_VALUES and PS_WR_EN_IN = '1' and PS_ACTIVATE_IN = '1') then
			save_ctr <= save_ctr + 1;
		end if;
	end if;
end process SAVE_CTR_PROC;

SAVE_VALUES_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			saved_transaction_id <= (others => '0');
			saved_proposed_ip    <= (others => '0');
			saved_dhcp_type      <= (others => '0');
		-- dissection of DHCP Offer message
		elsif (main_current_state = WAITING_FOR_OFFER and receive_current_state = SAVE_VALUES) then
		
			case save_ctr is
			
				when 5 =>
					saved_transaction_id(7 downto 0) <= PS_DATA_IN(7 downto 0);
				
				when 6 =>
					saved_transaction_id(15 downto 8) <= PS_DATA_IN(7 downto 0);
			
				when 7 =>
					saved_transaction_id(23 downto 16) <= PS_DATA_IN(7 downto 0);
					
				when 8 =>
					saved_transaction_id(31 downto 24) <= PS_DATA_IN(7 downto 0);
					
					
				when 17 =>
					saved_proposed_ip(7 downto 0) <= PS_DATA_IN(7 downto 0);
				
				when 18 =>
					saved_proposed_ip(15 downto 8) <= PS_DATA_IN(7 downto 0);
					
				when 19 =>
					saved_proposed_ip(23 downto 16) <= PS_DATA_IN(7 downto 0);
					
				when 20 =>
					saved_proposed_ip(31 downto 24) <= PS_DATA_IN(7 downto 0);
					
				when 241 =>
					saved_dhcp_type(7 downto 0) <= PS_DATA_IN(7 downto 0);
					
				when 242 =>
					saved_dhcp_type(15 downto 8) <= PS_DATA_IN(7 downto 0);
					
				when 243 =>
					saved_dhcp_type(23 downto 16) <= PS_DATA_IN(7 downto 0);
					
				when others => null;
					
			end case;
		-- dissection on DHCP Ack message
		elsif (main_current_state = WAITING_FOR_ACK and receive_current_state = SAVE_VALUES) then
		
			case save_ctr is
			
				when 5 =>
					saved_transaction_id(7 downto 0) <= PS_DATA_IN(7 downto 0);
				
				when 6 =>
					saved_transaction_id(15 downto 8) <= PS_DATA_IN(7 downto 0);
			
				when 7 =>
					saved_transaction_id(23 downto 16) <= PS_DATA_IN(7 downto 0);
					
				when 8 =>
					saved_transaction_id(31 downto 24) <= PS_DATA_IN(7 downto 0);
					
					
				when 13 =>
					saved_true_ip(7 downto 0) <= PS_DATA_IN(7 downto 0);
				
				when 14 =>
					saved_true_ip(15 downto 8) <= PS_DATA_IN(7 downto 0);
					
				when 15 =>
					saved_true_ip(23 downto 16) <= PS_DATA_IN(7 downto 0);
					
				when 16 =>
					saved_true_ip(31 downto 24) <= PS_DATA_IN(7 downto 0);
					
					
				when 241 =>
					saved_dhcp_type(7 downto 0) <= PS_DATA_IN(7 downto 0);
					
				when 242 =>
					saved_dhcp_type(15 downto 8) <= PS_DATA_IN(7 downto 0);
					
				when 243 =>
					saved_dhcp_type(23 downto 16) <= PS_DATA_IN(7 downto 0);
					
				when others => null;
					
			end case;		
				
		end if;
	end if;
end process SAVE_VALUES_PROC;


CONSTRUCT_MACHINE_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			construct_current_state <= IDLE;
		else
			construct_current_state <= construct_next_state;
		end if;
	end if;
end process CONSTRUCT_MACHINE_PROC;

CONSTRUCT_MACHINE : process(construct_current_state, main_current_state, load_ctr)
begin
	case construct_current_state is
	
		when IDLE =>
			state <= x"1";
			if (main_current_state = SENDING_DISCOVER) or (main_current_state = SENDING_REQUEST) then
				construct_next_state <= BOOTP_HEADERS;
			else
				construct_next_state <= IDLE;
			end if;
			
		when BOOTP_HEADERS =>
			state <= x"3";
			if (load_ctr = 11) then
				construct_next_state <= CLIENT_IP;
			else
				construct_next_state <= BOOTP_HEADERS;
			end if;
			
		when CLIENT_IP =>
			state <= x"5";
			if (load_ctr = 15) then
				construct_next_state <= YOUR_IP;
			else
				construct_next_state <= CLIENT_IP;
			end if;
			
		when YOUR_IP => 
			state <= x"b";
			if (load_ctr = 19) then
				construct_next_state <= ZEROS1;
			else
				construct_next_state <= YOUR_IP;
			end if;
			
		when ZEROS1 =>
			state <= x"c";
			if (load_ctr = 27) then
				construct_next_state <= MY_MAC;
			else
				construct_next_state <= ZEROS1;
			end if;
		
		when MY_MAC =>
			state <= x"6";
			if (load_ctr = 33) then
				construct_next_state <= ZEROS2;
			else
				construct_next_state <= MY_MAC;
			end if;
		
		when ZEROS2 =>
			state <= x"7";
			if (load_ctr = 235) then
				construct_next_state <= VENDOR_VALS;
			else
				construct_next_state <= ZEROS2;
			end if;
			
		when VENDOR_VALS =>
			state <= x"8";
			if (load_ctr = 258) then
				construct_next_state <= CLEANUP;
			else
				construct_next_state <= VENDOR_VALS;
			end if;
		
		when CLEANUP =>
			state <= x"9";
			construct_next_state <= IDLE;
	
	end case;
end process CONSTRUCT_MACHINE;

LOAD_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (construct_current_state = IDLE) then
			load_ctr <= 0;
		elsif (TC_RD_EN_IN = '1') and (PS_SELECTED_IN = '1') then
			load_ctr <= load_ctr + 1;
		end if;
	end if;
end process LOAD_CTR_PROC;

TC_DATA_PROC : process(construct_current_state, load_ctr, bootp_hdr, my_mac_addr)
begin

	tc_data(8) <= '0';

	case (construct_current_state) is

		when BOOTP_HEADERS =>
			for i in 0 to 7 loop
				tc_data(i) <= bootp_hdr(load_ctr * 8 + i);
			end loop;
			
		when CLIENT_IP =>
			if (main_current_state = SENDING_DISCOVER) then
				tc_data(7 downto 0) <= x"00";
			elsif (main_current_state = SENDING_REQUEST) then
				for i in 0 to 7 loop
					tc_data(i) <= saved_proposed_ip((load_ctr - 12) * 8 + i);
				end loop;
			end if;
		
		when YOUR_IP =>
			tc_data(7 downto 0) <= x"00";
		
		when ZEROS1 =>
			tc_data(7 downto 0) <= x"00";
		
		when MY_MAC =>
			for i in 0 to 7 loop
				tc_data(i) <= my_mac_addr((load_ctr - 28) * 8 + i);
			end loop;
		
		when ZEROS2 =>
			tc_data(7 downto 0) <= x"00";
			
		when VENDOR_VALS =>
			for i in 0 to 7 loop
				tc_data(i) <= vendor_values((load_ctr - 236) * 8 + i);
			end loop;
			-- mark the last byte
			if (load_ctr = 258) then
				tc_data(8) <= '1';
			end if;
		
		when others => tc_data(7 downto 0) <= x"00";
	
	end case;
	
end process;

TC_DATA_SYNC : process(CLK)
begin
	if rising_edge(CLK) then
		TC_DATA_OUT <= tc_data;
	end if;
end process TC_DATA_SYNC;


PS_BUSY_OUT <= '0' when (construct_current_state = IDLE) else '1';

-- change this damn line
PS_RESPONSE_READY_OUT <= '1' when (construct_current_state = BOOTP_HEADERS or construct_current_state = CLIENT_IP or construct_current_state = YOUR_IP or construct_current_state = ZEROS1 or construct_current_state = MY_MAC or construct_current_state = ZEROS2 or construct_current_state = VENDOR_VALS or construct_current_state = CLEANUP)
			else '0';

TC_FRAME_SIZE_OUT <= x"0103";  -- fixe frame size for discover and request

TC_FRAME_TYPE_OUT <= x"0008";  -- frame type: ip 

-- for debug no receiveing frames but constructed bytes
REC_FRAMES_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			rec_frames <= (others => '0');
		elsif (receive_current_state = IDLE and PS_WR_EN_IN = '1' and PS_ACTIVATE_IN = '1') then
		--elsif (construct_current_state /= IDLE and construct_current_state /= CLEANUP and PS_SELECTED_IN = '1' and TC_RD_EN_IN = '1') then
			rec_frames <= rec_frames + x"1";
		end if;
	end if;
end process REC_FRAMES_PROC;

SENT_FRAMES_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			sent_frames <= (others => '0');
		elsif (construct_current_state = CLEANUP) then
			sent_frames <= sent_frames + x"1";
		end if;
	end if;
end process SENT_FRAMES_PROC;

RECEIVED_FRAMES_OUT <= rec_frames;
SENT_FRAMES_OUT     <= sent_frames;

-- **** debug
DEBUG_OUT(3 downto 0)   <= state;
DEBUG_OUT(11 downto 4)  <= x"ff" when main_current_state = ESTABLISHED else x"55";
DEBUG_OUT(31 downto 12) <= wait_ctr(31 downto 12);
-- ****

end trb_net16_gbe_response_constructor_DHCP;


