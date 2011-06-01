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
-- here all frame checking has to be done, if the frame fits into protocol standards
-- if so FR_FRAME_VALID_OUT is asserted after having received all bytes of a frame
-- otherwise, after receiving all bytes, FR_FRAME_VALID_OUT keeps low and the fifo is cleared
-- also a part of addresses assignemt has to be done here

entity trb_net16_gbe_frame_receiver is
port (
	CLK			: in	std_logic;  -- system clock
	RESET			: in	std_logic;
	LINK_OK_IN              : in    std_logic;
	ALLOW_RX_IN		: in	std_logic;
	ALLOW_BRDCST_ETH_IN	: in	std_logic;
	ALLOW_BRDCST_IP_IN	: in	std_logic;
	MY_MAC_IN		: in	std_logic_vector(47 downto 0);
	RX_MAC_CLK		: in	std_logic;  -- receiver serdes clock

-- input signals from TS_MAC
	MAC_RX_EOF_IN		: in	std_logic;
	MAC_RX_ER_IN		: in	std_logic;
	MAC_RXD_IN		: in	std_logic_vector(7 downto 0);
	MAC_RX_EN_IN		: in	std_logic;
	MAC_RX_FIFO_ERR_IN	: in	std_logic;
	MAC_RX_FIFO_FULL_OUT	: out	std_logic;
	MAC_RX_STAT_EN_IN	: in	std_logic;
	MAC_RX_STAT_VEC_IN	: in	std_logic_vector(31 downto 0);

-- output signal to control logic
	FR_Q_OUT		: out	std_logic_vector(8 downto 0);
	FR_RD_EN_IN		: in	std_logic;
	FR_FRAME_VALID_OUT	: out	std_logic;
	FR_GET_FRAME_IN		: in	std_logic;
	FR_FRAME_SIZE_OUT	: out	std_logic_vector(15 downto 0);
	FR_FRAME_PROTO_OUT	: out	std_logic_vector(15 downto 0);  -- high level protocol name, see description for full list
	FR_ALLOWED_TYPES_IN	: in	std_logic_vector(31 downto 0);
	FR_ALLOWED_IP_IN	: in	std_logic_vector(31 downto 0);
	FR_ALLOWED_UDP_IN	: in	std_logic_vector(31 downto 0);
	FR_VLAN_ID_IN		: in	std_logic_vector(31 downto 0);
	
	FR_SRC_MAC_ADDRESS_OUT	: out	std_logic_vector(47 downto 0);
	FR_DEST_MAC_ADDRESS_OUT : out	std_logic_vector(47 downto 0);
	FR_SRC_IP_ADDRESS_OUT	: out	std_logic_vector(31 downto 0);
	FR_DEST_IP_ADDRESS_OUT	: out	std_logic_vector(31 downto 0);
	FR_SRC_UDP_PORT_OUT	: out	std_logic_vector(15 downto 0);
	FR_DEST_UDP_PORT_OUT	: out	std_logic_vector(15 downto 0);

	DEBUG_OUT		: out	std_logic_vector(63 downto 0)
);
end trb_net16_gbe_frame_receiver;


architecture trb_net16_gbe_frame_receiver of trb_net16_gbe_frame_receiver is

-- attribute HGROUP : string;
-- attribute HGROUP of trb_net16_gbe_frame_receiver : architecture is "GBE_frame_rec";
attribute syn_encoding	: string;
type filter_states is (IDLE, REMOVE_DEST, REMOVE_SRC, REMOVE_TYPE, SAVE_FRAME, DROP_FRAME, REMOVE_VID, REMOVE_VTYPE, REMOVE_IP, REMOVE_UDP, DECIDE, CLEANUP);
signal filter_current_state, filter_next_state : filter_states;
attribute syn_encoding of filter_current_state : signal is "safe,gray";

signal fifo_wr_en                           : std_logic;
signal rx_bytes_ctr                         : std_logic_vector(15 downto 0);
signal frame_valid_q                        : std_logic;
signal delayed_frame_valid                  : std_logic;
signal delayed_frame_valid_q                : std_logic;

signal rec_fifo_empty                       : std_logic;
signal rec_fifo_full                        : std_logic;
signal sizes_fifo_full                      : std_logic;
signal sizes_fifo_empty                     : std_logic;

signal remove_ctr                           : std_logic_vector(7 downto 0);
signal new_frame                            : std_logic;
signal new_frame_lock                       : std_logic;
signal saved_frame_type                     : std_logic_vector(15 downto 0);
signal saved_vid                            : std_logic_vector(15 downto 0);
signal saved_src_mac                        : std_logic_vector(47 downto 0);
signal saved_dest_mac                       : std_logic_vector(47 downto 0);
signal frame_type_valid                     : std_logic;
signal saved_proto                          : std_logic_vector(7 downto 0);
signal saved_src_ip                         : std_logic_vector(31 downto 0);
signal saved_dest_ip                        : std_logic_vector(31 downto 0);
signal saved_src_udp                        : std_logic_vector(15 downto 0);
signal saved_dest_udp                       : std_logic_vector(15 downto 0);


-- debug signals
signal dbg_rec_frames                       : std_logic_vector(15 downto 0);
signal dbg_ack_frames                       : std_logic_vector(15 downto 0);
signal dbg_drp_frames                       : std_logic_vector(15 downto 0);
signal state                                : std_logic_vector(3 downto 0);

begin

DEBUG_OUT(0)            <= rec_fifo_empty;
DEBUG_OUT(1)            <= rec_fifo_full;
DEBUG_OUT(2)            <= sizes_fifo_empty;
DEBUG_OUT(3)            <= sizes_fifo_full;
DEBUG_OUT(7 downto 4)   <= state;
DEBUG_OUT(15 downto 8)  <= (others => '1');
DEBUG_OUT(31 downto 16) <= dbg_rec_frames;
DEBUG_OUT(47 downto 32) <= dbg_ack_frames;
DEBUG_OUT(63 downto 48) <= dbg_drp_frames;


-- new_frame is asserted when first byte of the frame arrives
NEW_FRAME_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') or (MAC_RX_EOF_IN = '1') then
			new_frame <= '0';
			new_frame_lock <= '0';
		elsif (new_frame_lock = '0') and (MAC_RX_EN_IN = '1') then
			new_frame <= '1';
			new_frame_lock <= '1';
		else
			new_frame <= '0';
		end if;
	end if;
end process NEW_FRAME_PROC;


FILTER_MACHINE_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') then
			filter_current_state <= IDLE;
		else
			filter_current_state <= filter_next_state;
		end if;
	end if;
end process FILTER_MACHINE_PROC;

FILTER_MACHINE : process(filter_current_state, remove_ctr, new_frame, MAC_RX_EOF_IN, frame_type_valid, ALLOW_RX_IN)
begin

	case filter_current_state is
		
		when IDLE =>
			state <= x"1";
			if (new_frame = '1') and (ALLOW_RX_IN = '1') then
				filter_next_state <= REMOVE_DEST;
			else
				filter_next_state <= IDLE;
			end if;
		
		-- frames arrive without preamble!
		when REMOVE_DEST =>
			state <= x"3";
			if (remove_ctr = x"03") then  -- counter starts with a delay that's why only 3
				-- destination MAC address filtering here 
				if (saved_dest_mac = MY_MAC_IN) then
					filter_next_state <= REMOVE_SRC;
				elsif (ALLOW_BRDCST_ETH_IN = '1') and (saved_dest_mac = x"ffffffffffff") then
					filter_next_state <= REMOVE_SRC;
				else
					filter_next_state <= DECIDE;
				end if;
			else
				filter_next_state <= REMOVE_DEST;
			end if;
		
		when REMOVE_SRC =>
			state <= x"4";
			if (remove_ctr = x"09") then
				filter_next_state <= REMOVE_TYPE;
			else
				filter_next_state <= REMOVE_SRC;
			end if;
		
		when REMOVE_TYPE =>
			state <= x"5";
			if (remove_ctr = x"0b") then
				if (saved_frame_type = x"8100") then  -- VLAN tagged frame
					filter_next_state <= REMOVE_VID;
				else  -- no VLAN tag
					if (saved_frame_type = x"0800") then  -- in case of IP continue removing headers
						filter_next_state <= REMOVE_IP;
					else
						filter_next_state <= DECIDE;
					end if;
				end if;
			else
				filter_next_state <= REMOVE_TYPE;
			end if;
			
		when REMOVE_VID =>
			state <= x"a";
			if (remove_ctr = x"0d") then
				filter_next_state <= REMOVE_VTYPE;
			else
				filter_next_state <= REMOVE_VID;
			end if;
			
		when REMOVE_VTYPE =>
			state <= x"b";
			if (remove_ctr = x"0f") then
				if (saved_frame_type = x"0800") then  -- in case of IP continue removing headers
					filter_next_state <= REMOVE_IP;
				else
					filter_next_state <= DECIDE;
				end if;
			else
				filter_next_state <= REMOVE_VTYPE;
			end if;
			
		when REMOVE_IP =>
			state <= x"c";
			if (remove_ctr = x"11") then
				if (saved_proto = x"11") then  -- forced to recognize udp only, TODO check all protocols
					filter_next_state <= REMOVE_UDP;
				else
					filter_next_state <= DECIDE;  -- changed from drop
				end if;
			else
				filter_next_state <= REMOVE_IP;
			end if;
			
		when REMOVE_UDP =>
			state <= x"d";
			if (remove_ctr = x"19") then
				filter_next_state <= DECIDE;
			else
				filter_next_state <= REMOVE_UDP;
			end if;
			
		when DECIDE =>
			state <= x"6";
			if (frame_type_valid = '1') then
				filter_next_state <= SAVE_FRAME;
			else
				filter_next_state <= DROP_FRAME;
			end if;	
			
		when SAVE_FRAME =>
			state <= x"7";
			if (MAC_RX_EOF_IN = '1') then
				filter_next_state <= CLEANUP;
			else
				filter_next_state <= SAVE_FRAME;
			end if;
			
		when DROP_FRAME =>
			state <= x"8";
			if (MAC_RX_EOF_IN = '1') then
				filter_next_state <= CLEANUP;
			else
				filter_next_state <= DROP_FRAME;
			end if;
		
		when CLEANUP =>
			state <= x"9";
			filter_next_state <= IDLE;
			
		when others => null;
	
	end case;
end process;

-- counts the bytes to be removed from the ethernet headers fields
REMOVE_CTR_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') or (filter_current_state = IDLE) or
			(filter_current_state = REMOVE_VTYPE and remove_ctr = x"0f") or
			(filter_current_state = REMOVE_TYPE and remove_ctr = x"0b") then
			
			remove_ctr <= (others => '1');
		elsif (MAC_RX_EN_IN = '1') and (filter_current_state /= IDLE) then --and (filter_current_state /= CLEANUP) then
			remove_ctr <= remove_ctr + x"1";
		end if;
	end if;
end process REMOVE_CTR_PROC;

SAVED_PROTO_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') or (filter_current_state = CLEANUP) then
			saved_proto <= (others => '0');
		elsif (filter_current_state = REMOVE_IP) and (remove_ctr = x"07") then
			saved_proto <= MAC_RXD_IN;
		end if;
	end if;
end process SAVED_PROTO_PROC;

SAVED_SRC_IP_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') or (filter_current_state = CLEANUP) then
			saved_src_ip <= (others => '0');
		elsif (filter_current_state = REMOVE_IP) and (remove_ctr = x"0a") then
			saved_src_ip(7 downto 0) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_IP) and (remove_ctr = x"0b") then
			saved_src_ip(15 downto 8) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_IP) and (remove_ctr = x"0c") then
			saved_src_ip(23 downto 16) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_IP) and (remove_ctr = x"0d") then
			saved_src_ip(31 downto 24) <= MAC_RXD_IN;
		end if;
	end if;
end process SAVED_SRC_IP_PROC;

SAVED_DEST_IP_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') or (filter_current_state = CLEANUP) then
			saved_dest_ip <= (others => '0');
		elsif (filter_current_state = REMOVE_IP) and (remove_ctr = x"0e") then
			saved_dest_ip(7 downto 0) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_IP) and (remove_ctr = x"0f") then
			saved_dest_ip(15 downto 8) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_IP) and (remove_ctr = x"10") then
			saved_dest_ip(23 downto 16) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_IP) and (remove_ctr = x"11") then
			saved_dest_ip(31 downto 24) <= MAC_RXD_IN;
		end if;
	end if;
end process SAVED_DEST_IP_PROC;

SAVED_SRC_UDP_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') or (filter_current_state = CLEANUP) then
			saved_src_udp <= (others => '0');
		elsif (filter_current_state = REMOVE_UDP) and (remove_ctr = x"12") then
			saved_src_udp(15 downto 8) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_UDP) and (remove_ctr = x"13") then
			saved_src_udp(7 downto 0) <= MAC_RXD_IN;
		end if;
	end if;
end process SAVED_SRC_UDP_PROC;

SAVED_DEST_UDP_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') or (filter_current_state = CLEANUP) then
			saved_dest_udp <= (others => '0');
		elsif (filter_current_state = REMOVE_UDP) and (remove_ctr = x"14") then
			saved_dest_udp(15 downto 8) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_UDP) and (remove_ctr = x"15") then
			saved_dest_udp(7 downto 0) <= MAC_RXD_IN;
		end if;
	end if;
end process SAVED_DEST_UDP_PROC;

-- saves the destination mac address of the incoming frame
SAVED_DEST_MAC_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') or (filter_current_state = CLEANUP) then
			saved_dest_mac <= (others => '0');
		elsif (filter_current_state = IDLE) and (MAC_RX_EN_IN = '1') and (new_frame = '0') then
			saved_dest_mac(7 downto 0) <= MAC_RXD_IN;
		elsif (filter_current_state = IDLE) and (new_frame = '1') and (ALLOW_RX_IN = '1') then
			saved_dest_mac(15 downto 8) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_DEST) and (remove_ctr = x"FF") then
			saved_dest_mac(23 downto 16) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_DEST) and (remove_ctr = x"00") then
			saved_dest_mac(31 downto 24) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_DEST) and (remove_ctr = x"01") then
			saved_dest_mac(39 downto 32) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_DEST) and (remove_ctr = x"02") then
			saved_dest_mac(47 downto 40) <= MAC_RXD_IN;
		end if;
	end if;
end process SAVED_DEST_MAC_PROC;

-- saves the source mac address of the incoming frame
SAVED_SRC_MAC_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') or (filter_current_state = CLEANUP) then
			saved_src_mac <= (others => '0');
		elsif (filter_current_state = REMOVE_DEST) and (remove_ctr = x"03") then
			saved_src_mac(7 downto 0) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_SRC) and (remove_ctr = x"04") then
			saved_src_mac(15 downto 8) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_SRC) and (remove_ctr = x"05") then
			saved_src_mac(23 downto 16) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_SRC) and (remove_ctr = x"06") then
			saved_src_mac(31 downto 24) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_SRC) and (remove_ctr = x"07") then
			saved_src_mac(39 downto 32) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_SRC) and (remove_ctr = x"08") then
			saved_src_mac(47 downto 40) <= MAC_RXD_IN;
		end if;
	end if;
end process SAVED_SRC_MAC_PROC;

-- saves the frame type of the incoming frame for futher check
SAVED_FRAME_TYPE_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') or (filter_current_state = CLEANUP) then
			saved_frame_type <= (others => '0');
		elsif (filter_current_state = REMOVE_SRC) and (remove_ctr = x"09") then
			saved_frame_type(15 downto 8) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_TYPE) and (remove_ctr = x"0a") then
			saved_frame_type(7 downto 0) <= MAC_RXD_IN;
		-- two more cases for VLAN tagged frame
		elsif (filter_current_state = REMOVE_VID) and (remove_ctr = x"0d") then
			saved_frame_type(15 downto 8) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_VTYPE) and (remove_ctr = x"0e") then
			saved_frame_type(7 downto 0) <= MAC_RXD_IN;
		end if;
	end if;
end process SAVED_FRAME_TYPE_PROC;

-- saves VLAN id when tagged frame spotted
SAVED_VID_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') or (filter_current_state = CLEANUP) then
			saved_vid <= (others => '0');
		elsif (filter_current_state = REMOVE_TYPE and remove_ctr = x"0b" and saved_frame_type = x"8100") then
			saved_vid(15 downto 8) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_VID and remove_ctr = x"0c") then
			saved_vid(7 downto 0) <= MAC_RXD_IN;
		end if;
	end if;
end process SAVED_VID_PROC;

type_validator : trb_net16_gbe_type_validator
port map(
	FRAME_TYPE_IN		=> saved_frame_type,
	SAVED_VLAN_ID_IN	=> saved_vid,	
	ALLOWED_TYPES_IN	=> FR_ALLOWED_TYPES_IN,
	VLAN_ID_IN		=> FR_VLAN_ID_IN,
	
	-- IP level
	IP_PROTOCOLS_IN		=> saved_proto,
	ALLOWED_IP_PROTOCOLS_IN	=> FR_ALLOWED_IP_IN,
	
	-- UDP level
	UDP_PROTOCOL_IN		 => saved_dest_udp,
	ALLOWED_UDP_PROTOCOLS_IN => FR_ALLOWED_UDP_IN,
	
	VALID_OUT		=> frame_type_valid
);

--TODO put here a larger fifo maybe (for sure!)
receive_fifo : fifo_4096x9
port map( 
	Data(7 downto 0)    => MAC_RXD_IN,
	Data(8)             => MAC_RX_EOF_IN,
	WrClock             => RX_MAC_CLK,
	RdClock             => CLK,
	WrEn                => fifo_wr_en,
	RdEn                => FR_RD_EN_IN,
	Reset               => RESET,
	RPReset             => RESET,
	Q                   => FR_Q_OUT,
	Empty               => rec_fifo_empty,
	Full                => rec_fifo_full
);

fifo_wr_en <= '1' when (MAC_RX_EN_IN = '1') and ((filter_current_state = SAVE_FRAME) or 
			( ((filter_current_state = REMOVE_TYPE and remove_ctr = x"b" and saved_frame_type /= x"8100" and saved_frame_type /= x"0800") or
				(filter_current_state = REMOVE_VTYPE and remove_ctr = x"f") or
				(filter_current_state = DECIDE)) and frame_type_valid = '1'))
	      else '0';

MAC_RX_FIFO_FULL_OUT <= rec_fifo_full;

sizes_fifo : fifo_512x32
port map( 
	Data(15 downto 0)   => rx_bytes_ctr,
	Data(31 downto 16)  => saved_frame_type,
	WrClock             => RX_MAC_CLK,
	RdClock             => CLK,
	WrEn                => frame_valid_q,
	RdEn                => FR_GET_FRAME_IN,
	Reset               => RESET,
	RPReset             => RESET,
	Q(15 downto 0)      => FR_FRAME_SIZE_OUT,
	Q(31 downto 16)     => FR_FRAME_PROTO_OUT,
	Empty               => sizes_fifo_empty,
	Full                => sizes_fifo_full
);

macs_fifo : fifo_512x64
port map( 
	Data(47 downto 0)   => saved_src_mac,
	Data(63 downto 48)  => saved_src_udp,
	WrClock             => RX_MAC_CLK,
	RdClock             => CLK,
	WrEn                => frame_valid_q,
	RdEn                => FR_GET_FRAME_IN,
	Reset               => RESET,
	RPReset             => RESET,
	Q(47 downto 0)      => FR_SRC_MAC_ADDRESS_OUT,
	Q(63 downto 48)     => FR_SRC_UDP_PORT_OUT,
	Empty               => open,
	Full                => open
);

macd_fifo : fifo_512x64
port map( 
	Data(47 downto 0)   => saved_dest_mac,
	Data(63 downto 48)  => saved_dest_udp,
	WrClock             => RX_MAC_CLK,
	RdClock             => CLK,
	WrEn                => frame_valid_q,
	RdEn                => FR_GET_FRAME_IN,
	Reset               => RESET,
	RPReset             => RESET,
	Q(47 downto 0)      => FR_DEST_MAC_ADDRESS_OUT,
	Q(63 downto 48)     => FR_DEST_UDP_PORT_OUT,
	Empty               => open,
	Full                => open
);

ip_fifo : fifo_512x64
port map( 
	Data(31 downto 0)   => saved_src_ip,
	Data(63 downto 32)  => saved_dest_ip,
	WrClock             => RX_MAC_CLK,
	RdClock             => CLK,
	WrEn                => frame_valid_q,
	RdEn                => FR_GET_FRAME_IN,
	Reset               => RESET,
	RPReset             => RESET,
	Q(31 downto 0)      => FR_SRC_IP_ADDRESS_OUT,
	Q(63 downto 32)     => FR_DEST_IP_ADDRESS_OUT,
	Empty               => open,
	Full                => open
);

FRAME_VALID_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (MAC_RX_EOF_IN = '1' and ALLOW_RX_IN = '1' and frame_type_valid = '1') then
			frame_valid_q <= '1';
		else
			frame_valid_q <= '0';
		end if;
	end if;
end process FRAME_VALID_PROC;
--frame_valid_q <= '1' when (MAC_RX_EOF_IN = '1' and ALLOW_RX_IN = '1') and (frame_type_valid = '1')
--		    else '0';

-- received bytes counter is valid only after FR_FRAME_VALID_OUT is asserted for few clock cycles
RX_BYTES_CTR_PROC : process(RX_MAC_CLK)
begin
  if rising_edge(RX_MAC_CLK) then
    if (RESET = '1') or (delayed_frame_valid_q = '1') then
      rx_bytes_ctr <= (others => '0');
    elsif (fifo_wr_en = '1') then
      rx_bytes_ctr <= rx_bytes_ctr + x"1";
    end if;
  end if;
end process;


SYNC_PROC : process(RX_MAC_CLK)
begin
  if rising_edge(RX_MAC_CLK) then
    delayed_frame_valid   <= MAC_RX_EOF_IN;
    delayed_frame_valid_q <= delayed_frame_valid;
  end if;
end process SYNC_PROC;

--*****************
-- synchronization between 125MHz receive clock and 100MHz system clock
FRAME_VALID_SYNC : pulse_sync
port map(
	CLK_A_IN    => RX_MAC_CLK,
	RESET_A_IN  => RESET,
	PULSE_A_IN  => frame_valid_q,
	CLK_B_IN    => CLK,
	RESET_B_IN  => RESET,
	PULSE_B_OUT => FR_FRAME_VALID_OUT
);


-- ****
-- debug counters, to be removed later
RECEIVED_FRAMES_CTR : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') then
			dbg_rec_frames <= (others => '0');
		elsif (MAC_RX_EOF_IN = '1') then
			dbg_rec_frames <= dbg_rec_frames + x"1";
		end if;
	end if;
end process RECEIVED_FRAMES_CTR;

ACK_FRAMES_CTR : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') then
			dbg_ack_frames <= (others => '0');
		elsif (filter_current_state = DECIDE and frame_type_valid = '1') then
			dbg_ack_frames <= dbg_ack_frames + x"1";
		end if;
	end if;
end process ACK_FRAMES_CTR;

DROPPED_FRAMES_CTR : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') then
			dbg_drp_frames <= (others => '0');
		elsif (filter_current_state = DECIDE and frame_type_valid = '0') then
			dbg_drp_frames <= dbg_drp_frames + x"1";
		end if;
	end if;
end process DROPPED_FRAMES_CTR;

-- end of debug counters
-- ****

end trb_net16_gbe_frame_receiver;


