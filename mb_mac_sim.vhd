LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;
use IEEE.std_logic_arith.all;

library work;
--use work.trb_net_std.all;
--use work.trb_net_components.all;
--use work.trb_net16_hub_func.all;

entity mb_mac_sim is
port (
	--------------------------------------------------------------------------
	--------------- clock, reset, clock enable -------------------------------
	HCLK				: in	std_logic;
	TX_MAC_CLK			: in	std_logic;
	RX_MAC_CLK			: in	std_logic;
	RESET_N				: in	std_logic;
	TXMAC_CLK_EN		: in	std_logic;
	RXMAC_CLK_EN		: in	std_logic;
	--------------------------------------------------------------------------
	--------------- SGMII receive interface ----------------------------------
	RXD					: in	std_logic_vector(7 downto 0);
	RX_DV				: in	std_logic;
	RX_ER				: in	std_logic;
	COL					: in	std_logic;
	CRS					: in	std_logic;
	--------------------------------------------------------------------------
	--------------- SGMII transmit interface ---------------------------------
	TXD					: out	std_logic_vector(7 downto 0);
	TX_EN				: out	std_logic;
	TX_ER				: out	std_logic;
	--------------------------------------------------------------------------
	--------------- CPU configuration interface ------------------------------
	HADDR				: in	std_logic_vector(7 downto 0);
	HDATAIN				: in	std_logic_vector(7 downto 0);
	HCS_N				: in	std_logic;
	HWRITE_N			: in	std_logic;
	HREAD_N				: in	std_logic;
	HDATAOUT			: out	std_logic_vector(7 downto 0);
	HDATAOUT_EN_N		: out	std_logic;
	HREADY_N			: out	std_logic;
	CPU_IF_GBIT_EN		: out	std_logic;
	--------------------------------------------------------------------------
	--------------- Transmit FIFO interface ----------------------------------
	TX_FIFODATA			: in	std_logic_vector(7 downto 0);
	TX_FIFOAVAIL		: in	std_logic;
	TX_FIFOEOF			: in	std_logic;
	TX_FIFOEMPTY		: in	std_logic;
	TX_MACREAD			: out	std_logic;
	TX_DONE				: out	std_logic;
	TX_SNDPAUSTIM		: in	std_logic_vector(15 downto 0);
	TX_SNDPAUSREQ		: in	std_logic;
	TX_FIFOCTRL			: in	std_logic;
	TX_DISCFRM			: out	std_logic;
	TX_STATEN			: out	std_logic;
	TX_STATVEC			: out	std_logic_vector(30 downto 0);
	--------------------------------------------------------------------------
	--------------- Receive FIFO interface -----------------------------------
	RX_DBOUT			: out	std_logic_vector(7 downto 0);
	RX_FIFO_FULL		: in	std_logic;
	IGNORE_PKT			: in	std_logic;	
	RX_FIFO_ERROR		: out	std_logic;
	RX_STAT_VECTOR		: out	std_logic_vector(31 downto 0);
	RX_STAT_EN			: out	std_logic;
	RX_WRITE			: out	std_logic;
	RX_EOF				: out	std_logic;
	RX_ERROR			: out	std_logic
);
end mb_mac_sim;

architecture mb_mac_sim of mb_mac_sim is


-- CPU interface stuff
type HC_STATES is (HC_SLEEP, HC_READ, HC_WRITE, HC_RACK, HC_WACK);
signal HC_CURRENT_STATE, HC_NEXT_STATE: HC_STATES;

signal hready_n_comb		: std_logic;
signal hready_n_buf			: std_logic;
signal hdataout_en_n_comb	: std_logic;
signal hdataout_en_n_buf	: std_logic;

-- TX stuff
type TX_STATES is (TX_SLEEP, TX_READ, TX_DELAY, TX_TRANS, TX_CHECK);
signal TX_CURRENT_STATE, TX_NEXT_STATE: TX_STATES;

signal tx_bsm				: std_logic_vector(3 downto 0);
signal tx_macread_comb		: std_logic;
signal tx_done_comb			: std_logic;
signal tx_done_buf			: std_logic;

signal preread_ctr			: std_logic_vector(3 downto 0); -- preread counter for TX
signal preread_ce_comb		: std_logic;
signal preread_rst_comb		: std_logic;
signal preread_done_comb	: std_logic;
signal read_on_comb			: std_logic;


begin

------------------------------------------------------------------------------
-- state machine for configuration interface
------------------------------------------------------------------------------
-- BUG: no register simulated here!

-- state registers
HC_STATE_MEM: process( HCLK ) 
begin
	if   ( RESET_N = '0' ) then
		HC_CURRENT_STATE  <= HC_SLEEP;
		hready_n_buf      <= '1';
		hdataout_en_n_buf <= '1';
	elsif( rising_edge(HCLK) ) then
		HC_CURRENT_STATE  <= HC_NEXT_STATE;
		hready_n_buf      <= hready_n_comb;
		hdataout_en_n_buf <= hdataout_en_n_comb;
	end if;
end process HC_STATE_MEM;

-- state transitions
HC_STATE_TRANSFORM: process( HC_CURRENT_STATE, HCS_N, HREAD_N, HWRITE_N )
begin
	HC_NEXT_STATE         <= HC_SLEEP; -- avoid latches
	hready_n_comb      <= '1';
	hdataout_en_n_comb <= '1';
	case HC_CURRENT_STATE is
		when HC_SLEEP	=>	if   ( (HCS_N = '0') and (HREAD_N = '0') ) then
								HC_NEXT_STATE <= HC_READ;
							elsif( (HCS_N = '0') and (HWRITE_N = '0') ) then
								HC_NEXT_STATE <= HC_WRITE;
							else
								HC_NEXT_STATE <= HC_SLEEP;
							end if;
		when HC_READ	=>	HC_NEXT_STATE <= HC_RACK;
							hdataout_en_n_comb <= '0';
							hready_n_comb      <= '0';
		when HC_RACK	=>	HC_NEXT_STATE <= HC_SLEEP;
		when HC_WRITE	=>	HC_NEXT_STATE <= HC_WACK;
							hready_n_comb      <= '0';
		when HC_WACK	=>	HC_NEXT_STATE <= HC_SLEEP;
		when others		=>	HC_NEXT_STATE <= HC_SLEEP;
	end case;
end process HC_STATE_TRANSFORM;	

HREADY_N      <= hready_n_buf;
HDATAOUT_EN_N <= hdataout_en_n_buf;

------------------------------------------------------------------------------
-- state machine for "transmission"
------------------------------------------------------------------------------

-- preread counter
THE_PREREAD_CTR: process( TX_MAC_CLK )
begin
	if   ( RESET_N = '0' ) then
		preread_ctr <= (others => '0');
	elsif( rising_edge(TX_MAC_CLK) ) then
		if   ( preread_rst_comb = '1' ) then
			preread_ctr <= (others => '0');
		elsif( preread_ce_comb = '1' ) then
			preread_ctr <= preread_ctr + 1;	
		end if;
	end if; 
end process THE_PREREAD_CTR;
preread_done_comb <= '1' when (preread_ctr = x"6") 
						 else '0';

-- state registers
TX_STATE_MEM: process( TX_MAC_CLK, RESET_N ) 
begin
	if   ( RESET_N = '0' ) then
		TX_CURRENT_STATE  <= TX_SLEEP;
		tx_done_buf       <= '0';
	elsif( rising_edge(TX_MAC_CLK) ) then
		TX_CURRENT_STATE  <= TX_NEXT_STATE;
		tx_done_buf       <= tx_done_comb;
	end if;
end process TX_STATE_MEM;

tx_macread_comb <= preread_ce_comb or read_on_comb;

-- state transitions
TX_STATE_TRANSFORM: process( TX_CURRENT_STATE, TX_FIFOEMPTY, TX_FIFOAVAIL, TX_FIFOEOF, preread_done_comb )
begin
	TX_NEXT_STATE         <= TX_SLEEP; -- avoid latches
	preread_ce_comb       <= '0';
	preread_rst_comb      <= '0';
	read_on_comb          <= '0';
	tx_done_comb          <= '0';
	case TX_CURRENT_STATE is
		when TX_SLEEP	=>	tx_bsm <= x"0";
							if( TX_FIFOEMPTY = '0' ) then
								TX_NEXT_STATE <= TX_READ;
								preread_ce_comb <= '1';
							else
								TX_NEXT_STATE <= TX_SLEEP;
							end if;
		when TX_READ	=>	tx_bsm <= x"1";
							if   ( TX_FIFOEMPTY = '1' ) then
								TX_NEXT_STATE <= TX_DELAY;
								preread_rst_comb <= '1';
							elsif( (preread_done_comb = '1') and (TX_FIFOAVAIL = '0') ) then
								TX_NEXT_STATE <= TX_DELAY;
								preread_rst_comb <= '1';
							elsif( (preread_done_comb = '1') and (TX_FIFOAVAIL = '1') ) then
								TX_NEXT_STATE <= TX_TRANS;
								preread_rst_comb <= '1';
								read_on_comb     <= '1';
							else
								TX_NEXT_STATE <= TX_READ;
								preread_ce_comb <= '1';
							end if;
		when TX_DELAY	=>	tx_bsm <= x"2";
							if( TX_FIFOAVAIL = '1' ) then
								TX_NEXT_STATE <= TX_TRANS;
								read_on_comb     <= '1';
							else
								TX_NEXT_STATE <= TX_DELAY;
							end if;
		when TX_TRANS	=>	tx_bsm <= x"3";
							if( TX_FIFOEOF = '1' ) then
								TX_NEXT_STATE <= TX_CHECK;
								tx_done_comb  <= '1';  -- don't know if this is realistic
							else
								TX_NEXT_STATE <= TX_TRANS;
								read_on_comb     <= '1';
							end if;
		when TX_CHECK	=>	tx_bsm <= x"4";
							if( (TX_FIFOEMPTY = '0') and (TX_FIFOAVAIL = '1') ) then
								TX_NEXT_STATE <= TX_READ;
								preread_ce_comb <= '1';
							else
								TX_NEXT_STATE <= TX_SLEEP;
							end if;
		when others		=>	tx_bsm <= x"f";
							TX_NEXT_STATE <= TX_SLEEP;
	end case;
end process TX_STATE_TRANSFORM;




------------------------------------------------------------------------------
-- Fake signals
------------------------------------------------------------------------------
RX_DBOUT       <= preread_ctr & tx_bsm; -- x"00";
RX_FIFO_ERROR  <= '0';
RX_STAT_VECTOR <= x"0000_0000";
RX_STAT_EN     <= '0';
RX_WRITE       <= '0';
RX_EOF         <= '0';
RX_ERROR       <= '0';

TX_DISCFRM     <= '0';
TX_EN          <= '0';
TX_ER          <= '0';
TX_STATVEC     <= (others => '0');
TX_STATEN      <= '0';
TXD            <= x"00";

CPU_IF_GBIT_EN <= '0';

TX_DONE        <= tx_done_buf;
TX_MACREAD     <= tx_macread_comb;

HDATAOUT       <= x"00";


end mb_mac_sim;


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
