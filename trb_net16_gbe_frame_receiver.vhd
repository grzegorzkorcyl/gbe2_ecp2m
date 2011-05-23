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

	DEBUG_OUT		: out	std_logic_vector(63 downto 0)
);
end trb_net16_gbe_frame_receiver;


architecture trb_net16_gbe_frame_receiver of trb_net16_gbe_frame_receiver is

-- attribute HGROUP : string;
-- attribute HGROUP of trb_net16_gbe_frame_receiver : architecture is "GBE_frame_rec";
attribute syn_encoding	: string;
type filter_states is (IDLE, REMOVE_PRE, REMOVE_DEST, REMOVE_SRC, REMOVE_TYPE, SAVE_FRAME, DROP_FRAME, CLEANUP);
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
signal data_valid                           : std_logic;
signal saved_frame_type                     : std_logic_vector(15 downto 0);
signal frame_type_valid                     : std_logic;

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
DEBUG_OUT(15 downto 8)  <= (others => '0');
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

FILTER_MACHINE : process(filter_current_state, remove_ctr, new_frame, MAC_RX_EOF_IN, frame_type_valid)
begin

	case filter_current_state is
		
		when IDLE =>
			state <= x"1";
			if (new_frame = '1') then
				filter_next_state <= REMOVE_PRE;
			else
				filter_next_state <= IDLE;
			end if;
		
		when REMOVE_PRE =>
			state <= x"2";
			if (remove_ctr = x"05") then
				filter_next_state <= REMOVE_DEST;
			else
				filter_next_state <= REMOVE_PRE;
			end if;
		
		when REMOVE_DEST =>
			state <= "3";
			if (remove_ctr = x"0b") then
				filter_next_state <= REMOVE_SRC;
			else
				filter_next_state <= REMOVE_DEST;
			end if;
		
		when REMOVE_SRC =>
			state <= x"4";
			if (remove_ctr = x"13") then
				filter_next_state <= REMOVE_TYPE;
			else
				filter_next_state <= REMOVE_SRC;
			end if;
		
		when REMOVE_TYPE =>
			state <= x"5";
			if (remove_ctr = x"15") then
				if (frame_type_valid = '1') then
					filter_next_state <= SAVE_FRAME;
				else
					filter_next_state <= DROP_FRAME;
				end if;				
			else
				filter_next_state <= REMOVE_TYPE;
			end if;
			
		when SAVE_FRAME =>
			state <= x"6";
			-- TODO: high level protocol recognition should be done here
			-- TODO: mabye checksum checking at the end
			if (MAC_RX_EOF_IN = '1') then
				filter_next_state <= CLEANUP;
			else
				filter_next_state <= SAVE_FRAME;
			end if;
			
		when DROP_FRAME =>
			state <= x"7";
			if (MAC_RX_EOF_IN = '1') then
				filter_next_state <= CLEANUP;
			else
				filter_next_state <= DROP_FRAME;
			end if;
		
		when CLEANUP =>
			state <= x"8";
			filter_next_state <= IDLE;
	
	end case;
end process;

-- counts the bytes to be removed from the ethernet headers fields
REMOVE_CTR_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') or (filter_current_state = IDLE) then
			remove_ctr <= (others => '0');
		elsif (data_valid = '1') and (filter_current_state /= IDLE) and (filter_current_state /= CLEANUP) then
			remove_ctr <= remove_ctr + x"1";
		end if;
	end if;
end process REMOVE_CTR_PROC;

data_valid <= '1' when (MAC_RX_EN_IN = '1') and (ALLOW_RX_IN = '1') 
	      else '0';

-- saves the frame type of the incoming frame for futher check
SAVED_FRAME_TYPE_PROC : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') or (filter_current_state = CLEANUP) then
			saved_frame_type <= (others => '0');
		elsif (filter_current_state = REMOVE_SRC) and (remove_ctr = x"13") then
			saved_frame_type(15 downto 8) <= MAC_RXD_IN;
		elsif (filter_current_state = REMOVE_TYPE) and (remove_ctr = x"14") then
			saved_frame_type(7 downto 0) <= MAC_RXD_IN;
		end if;
	end if;
end process SAVED_FRAME_TYPE_PROC;

type_validator : trb_net16_gbe_type_validator
port map(
	FRAME_TYPE_IN		=> saved_frame_type,	
	ALLOWED_TYPES_IN	=> FR_ALLOWED_TYPES_IN,
	
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
fifo_wr_en <= '1' when (data_valid = '1') and ((filter_current_state = SAVE_FRAME) or (filter_current_state = REMOVE_TYPE and remove_ctr = x"15" and frame_type_valid = '1'))
	      else '0';

MAC_RX_FIFO_FULL_OUT <= rec_fifo_full;

-- TODO: and maybe smaller here
sizes_fifo : fifo_4096x32
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

frame_valid_q <= '1' when (MAC_RX_EOF_IN = '1' and ALLOW_RX_IN = '1') and (frame_type_valid = '1')
		    else '0';

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
FRAME_VALID_SYNC : signal_sync
  generic map(
    WIDTH    => 1,
    DEPTH    => 2
    )
  port map(
    RESET    => RESET,
    CLK0     => CLK,
    CLK1     => CLK,
    D_IN(0)  => frame_valid_q,
    D_OUT(0) => FR_FRAME_VALID_OUT
);
-- FRAME_SIZE_SYNC : signal_sync
--   generic map(
--     WIDTH    => 16,
--     DEPTH    => 2
--     )
--   port map(
--     RESET    => RESET,
--     CLK0     => CLK,
--     CLK1     => CLK,
--     D_IN     => rx_bytes_ctr,
--     D_OUT    => FR_FRAME_SIZE_OUT
-- );


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
		elsif (filter_current_state = REMOVE_TYPE and remove_ctr = x"15" and frame_type_valid = '1') then
			dbg_ack_frames <= dbg_ack_frames + x"1";
		end if;
	end if;
end process ACK_FRAMES_CTR;

DROPPED_FRAMES_CTR : process(RX_MAC_CLK)
begin
	if rising_edge(RX_MAC_CLK) then
		if (RESET = '1') then
			dbg_drp_frames <= (others => '0');
		elsif (filter_current_state = REMOVE_TYPE and remove_ctr = x"15" and frame_type_valid = '1') then
			dbg_drp_frames <= dbg_drp_frames + x"1";
		end if;
	end if;
end process DROPPED_FRAMES_CTR;



-- end of debug counters
-- ****

end trb_net16_gbe_frame_receiver;


