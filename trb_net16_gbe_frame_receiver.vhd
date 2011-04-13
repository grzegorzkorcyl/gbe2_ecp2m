LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;
use work.trb_net16_hub_func.all;

--********
-- here all frame checking has to be done, if the frame fits into protocol standards
-- if so FR_FRAME_VALID_OUT is asserted after having received all bytes of a frame
-- otherwise, after receiving all bytes, FR_FRAME_VALID_OUT keeps low and the fifo is cleared
-- also a part of addresses assignemt has to be done here
-- should also have some outputs indicating the type of received message
-- require a state machine that will recognize messages and control the receiving process


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

	DEBUG_OUT		: out	std_logic_vector(63 downto 0)
);
end trb_net16_gbe_frame_receiver;


architecture trb_net16_gbe_frame_receiver of trb_net16_gbe_frame_receiver is

-- attribute HGROUP : string;
-- attribute HGROUP of trb_net16_gbe_frame_receiver : architecture is "GBE_frame_rec";

--attribute syn_encoding	: string;
--attribute syn_encoding of macInitState: signal is "safe,gray";

component fifo_4096x9 is
port( 
	Data    : in    std_logic_vector(8 downto 0);
	WrClock : in    std_logic;
	RdClock : in    std_logic;
	WrEn    : in    std_logic;
	RdEn    : in    std_logic;
	Reset   : in    std_logic;
	RPReset : in    std_logic;
	Q       : out   std_logic_vector(8 downto 0);
	Empty   : out   std_logic;
	Full    : out   std_logic
);
end component;

-- used to save sizes of received frames in frame_receiver
component debug_fifo_2kx16 is
port( 
	Data    : in    std_logic_vector(15 downto 0);
	WrClock : in    std_logic;
	RdClock : in    std_logic;
	WrEn    : in    std_logic;
	RdEn    : in    std_logic;
	Reset   : in    std_logic;
	RPReset : in    std_logic;
	Q       : out   std_logic_vector(15 downto 0);
	Empty   : out   std_logic;
	Full    : out   std_logic
);
end component;

signal fifo_wr_en                           : std_logic;
signal rx_bytes_ctr                         : std_logic_vector(15 downto 0);
signal frame_valid_q                        : std_logic;
signal delayed_frame_valid                  : std_logic;
signal delayed_frame_valid_q                : std_logic;

signal size_fifo_wr_en                      : std_logic;
signal rec_fifo_empty                       : std_logic;
signal rec_fifo_full                        : std_logic;
signal sizes_fifo_full                      : std_logic;
signal sizes_fifo_empty                     : std_logic;

begin

DEBUG_OUT(0)            <= rec_fifo_empty;
DEBUG_OUT(1)            <= rec_fifo_full;
DEBUG_OUT(2)            <= sizes_fifo_empty;
DEBUG_OUT(3)            <= sizes_fifo_full;
DEBUG_OUT(31 downto 4)  <= (others => '0');


--TODO put here a larger fifo maybe
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
fifo_wr_en <= '1' when (MAC_RX_EN_IN = '1' and ALLOW_RX_IN = '1')
	      else '0';

MAC_RX_FIFO_FULL_OUT <= rec_fifo_full;

sizes_fifo : debug_fifo_2kx16
port map( 
	Data                => rx_bytes_ctr,
	WrClock             => RX_MAC_CLK,
	RdClock             => CLK,
	WrEn                => frame_valid_q, --size_fifo_wr_en,
	RdEn                => FR_GET_FRAME_IN,
	Reset               => RESET,
	RPReset             => RESET,
	Q                   => FR_FRAME_SIZE_OUT,
	Empty               => sizes_fifo_empty,
	Full                => sizes_fifo_full
);

-- SIZE_FIFO_WR_EN_PROC : process(RX_MAC_CLK)
-- begin
--   if rising_edge(RX_MAC_CLK) then 
--     if (frame_valid_q = '1') and (ALLOW_RX_IN = '1') then
--       size_fifo_wr_en <= '1';
--     else
--       size_fifo_wr_en <= '0';
--     end if;
--   end if;
-- end process SIZE_FIFO_WR_EN_PROC;


frame_valid_q <= '1' when (MAC_RX_EOF_IN = '1' and ALLOW_RX_IN = '1')
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


end trb_net16_gbe_frame_receiver;


