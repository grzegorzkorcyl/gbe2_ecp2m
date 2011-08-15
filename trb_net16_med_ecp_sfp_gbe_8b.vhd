LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.std_logic_ARITH.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;

entity trb_net16_med_ecp_sfp_gbe_8b is
-- gk 28.04.10
generic (
	USE_125MHZ_EXTCLK			: integer range 0 to 1 := 1
);
port(
	RESET					: in	std_logic;
	GSR_N					: in	std_logic;
	CLK_125_OUT				: out	std_logic;
	CLK_125_IN				: in	std_logic;  -- gk 28.04.10  used when intclk
	CLK_125_RX_OUT				: out	std_logic;
	--SGMII connection to frame transmitter (tsmac)
	FT_TX_CLK_EN_OUT			: out	std_logic;
	FT_RX_CLK_EN_OUT			: out	std_logic;
	FT_COL_OUT				: out	std_logic;
	FT_CRS_OUT				: out	std_logic;
	FT_TXD_IN				: in	std_logic_vector(7 downto 0);
	FT_TX_EN_IN				: in	std_logic;
	FT_TX_ER_IN				: in	std_logic;

	FT_RXD_OUT				: out	std_logic_vector(7 downto 0);
	FT_RX_EN_OUT				: out	std_logic;
	FT_RX_ER_OUT				: out	std_logic;
	--SFP Connection
	SD_RXD_P_IN				: in	std_logic;
	SD_RXD_N_IN				: in	std_logic;
	SD_TXD_P_OUT				: out	std_logic;
	SD_TXD_N_OUT				: out	std_logic;
	SD_REFCLK_P_IN				: in	std_logic;
	SD_REFCLK_N_IN				: in	std_logic;
	SD_PRSNT_N_IN				: in	std_logic; -- SFP Present ('0' = SFP in place, '1' = no SFP mounted)
	SD_LOS_IN				: in	std_logic; -- SFP Loss Of Signal ('0' = OK, '1' = no signal)
	SD_TXDIS_OUT				: out	std_logic; -- SFP disable
	-- Autonegotiation stuff 
	MR_RESET_IN				: in	std_logic;
	MR_MODE_IN				: in	std_logic;
	MR_ADV_ABILITY_IN			: in 	std_logic_vector(15 downto 0); -- should be x"0020
	MR_AN_LP_ABILITY_OUT			: out	std_logic_vector(15 downto 0); -- advert page from link partner
	MR_AN_PAGE_RX_OUT			: out	std_logic;
	MR_AN_COMPLETE_OUT			: out	std_logic; 
	MR_AN_ENABLE_IN				: in	std_logic;
	MR_RESTART_AN_IN			: in	std_logic;
	-- Status and control port
	STAT_OP					: out	std_logic_vector (15 downto 0);
	CTRL_OP					: in	std_logic_vector (15 downto 0);
	STAT_DEBUG				: out	std_logic_vector (63 downto 0);
	CTRL_DEBUG				: in	std_logic_vector (63 downto 0)
);
end entity;

architecture trb_net16_med_ecp_sfp_gbe_8b of trb_net16_med_ecp_sfp_gbe_8b is

-- Placer Directives
--attribute HGROUP : string;
-- for whole architecture
--attribute HGROUP of trb_net16_med_ecp_sfp_gbe_8b : architecture  is "media_interface_group";
attribute syn_sharing : string;
attribute syn_sharing of trb_net16_med_ecp_sfp_gbe_8b : architecture is "off";

component serdes_gbe_0_extclock_8b is
GENERIC (USER_CONFIG_FILE    :  String := "serdes_gbe_0_extclock_8b.txt");
port( refclkp					: in	std_logic;
	  refclkn					: in	std_logic;
	  hdinp0					: in	std_logic;
	  hdinn0					: in	std_logic;
	  hdoutp0					: out	std_logic;
	  hdoutn0					: out	std_logic;
	  ff_rxiclk_ch0				: in	std_logic;
	  ff_txiclk_ch0				: in	std_logic;
	  ff_ebrd_clk_0				: in	std_logic;
	  ff_txdata_ch0				: in	std_logic_vector (7 downto 0);
	  ff_rxdata_ch0				: out	std_logic_vector (7 downto 0);
	  ff_tx_k_cntrl_ch0			: in	std_logic;
	  ff_rx_k_cntrl_ch0			: out	std_logic;
	  ff_rxfullclk_ch0			: out	std_logic;
	  ff_xmit_ch0				: in	std_logic;
	  ff_correct_disp_ch0		: in	std_logic;
	  ff_disp_err_ch0			: out	std_logic;
	  ff_cv_ch0					: out	std_logic;
	  ff_rx_even_ch0			: out	std_logic;
	  ffc_rrst_ch0				: in	std_logic;
	  ffc_lane_tx_rst_ch0		: in	std_logic;
	  ffc_lane_rx_rst_ch0		: in	std_logic;
	  ffc_txpwdnb_ch0			: in	std_logic;
	  ffc_rxpwdnb_ch0			: in	std_logic;
	  ffs_rlos_lo_ch0			: out	std_logic;
	  ffs_ls_sync_status_ch0	: out	std_logic;
	  ffs_rlol_ch0				: out	std_logic;
	  oob_out_ch0				: out	std_logic;
	  ffc_macro_rst				: in	std_logic;
	  ffc_quad_rst				: in	std_logic;
	  ffc_trst					: in	std_logic;
	  ff_txfullclk				: out	std_logic;
	  ff_txhalfclk				: out	std_logic;
	  refck2core				: out	std_logic;
	  ffs_plol					: out	std_logic
	);
end component;

component serdes_gbe_0_intclock_8b is
   GENERIC (USER_CONFIG_FILE    :  String := "serdes_gbe_0_intclock_8b.txt");
 port (
   core_txrefclk : in std_logic;
   core_rxrefclk : in std_logic;
   hdinp0, hdinn0 : in std_logic;
   hdoutp0, hdoutn0 : out std_logic;
   ff_rxiclk_ch0, ff_txiclk_ch0, ff_ebrd_clk_0 : in std_logic;
   ff_txdata_ch0 : in std_logic_vector (7 downto 0);
   ff_rxdata_ch0 : out std_logic_vector (7 downto 0);
   ff_tx_k_cntrl_ch0 : in std_logic;
   ff_rx_k_cntrl_ch0 : out std_logic;
   ff_rxfullclk_ch0 : out std_logic;
   ff_xmit_ch0 : in std_logic;
   ff_correct_disp_ch0 : in std_logic;
   ff_disp_err_ch0, ff_cv_ch0 : out std_logic;
   ff_rx_even_ch0 : out std_logic;
   ffc_rrst_ch0 : in std_logic;
   ffc_lane_tx_rst_ch0 : in std_logic;
   ffc_lane_rx_rst_ch0 : in std_logic;
   ffc_txpwdnb_ch0 : in std_logic;
   ffc_rxpwdnb_ch0 : in std_logic;
   ffs_rlos_lo_ch0 : out std_logic;
   ffs_ls_sync_status_ch0 : out std_logic;
   ffs_rlol_ch0 : out std_logic;
   oob_out_ch0 : out std_logic;
   ffc_macro_rst : in std_logic;
   ffc_quad_rst : in std_logic;
   ffc_trst : in std_logic;
   ff_txfullclk : out std_logic;
   ff_txhalfclk : out std_logic;
   ffs_plol : out std_logic);

end component;

component sgmii_gbe_pcs32
port( rst_n                  : in	std_logic;
	  signal_detect          : in	std_logic;
	  gbe_mode               : in	std_logic;
	  sgmii_mode             : in	std_logic;
	  operational_rate       : in	std_logic_vector(1 downto 0);
	  debug_link_timer_short : in	std_logic;
	  rx_compensation_err    : out	std_logic;
	  tx_clk_125             : in	std_logic;                    
	  tx_clock_enable_source : out	std_logic;
	  tx_clock_enable_sink   : in	std_logic;          
	  tx_d                   : in	std_logic_vector(7 downto 0); 
	  tx_en                  : in	std_logic;       
	  tx_er                  : in	std_logic;       
	  rx_clk_125             : in	std_logic; 
	  rx_clock_enable_source : out	std_logic;
	  rx_clock_enable_sink   : in	std_logic;          
	  rx_d                   : out	std_logic_vector(7 downto 0);       
	  rx_dv                  : out	std_logic;  
	  rx_er                  : out	std_logic; 
	  col                    : out	std_logic;  
	  crs                    : out	std_logic;  
	  tx_data                : out	std_logic_vector(7 downto 0);  
	  tx_kcntl               : out	std_logic; 
	  tx_disparity_cntl      : out	std_logic; 
	  serdes_recovered_clk   : in	std_logic; 
	  rx_data                : in	std_logic_vector(7 downto 0);  
	  rx_even                : in	std_logic;  
	  rx_kcntl               : in	std_logic; 
	  rx_disp_err            : in	std_logic; 
	  rx_cv_err              : in	std_logic; 
	  rx_err_decode_mode     : in	std_logic; 
	  mr_an_complete         : out	std_logic; 
	  mr_page_rx             : out	std_logic; 
	  mr_lp_adv_ability      : out	std_logic_vector(15 downto 0); 
	  mr_main_reset          : in	std_logic; 
	  mr_an_enable           : in	std_logic; 
	  mr_restart_an          : in	std_logic; 
	  mr_adv_ability         : in	std_logic_vector(15 downto 0)  
	);
end component;

component trb_net16_lsm_sfp_gbe is
port( SYSCLK			: in	std_logic; -- fabric clock (100MHz)
	  RESET				: in	std_logic; -- synchronous reset
	  CLEAR				: in	std_logic; -- asynchronous reset, connect to '0' if not needed / available
	  -- status signals
	  SFP_MISSING_IN	: in	std_logic; -- SFP Missing ('1' = no SFP mounted, '0' = SFP in place)
	  SFP_LOS_IN		: in	std_logic; -- SFP Loss Of Signal ('0' = OK, '1' = no signal)
	  SD_LINK_OK_IN		: in	std_logic; -- SerDes Link OK ('0' = not linked, '1' link established)
	  SD_LOS_IN			: in	std_logic; -- SerDes Loss Of Signal ('0' = OK, '1' = signal lost)
	  SD_TXCLK_BAD_IN	: in	std_logic; -- SerDes Tx Clock locked ('0' = locked, '1' = not locked)
	  SD_RXCLK_BAD_IN	: in	std_logic; -- SerDes Rx Clock locked ('0' = locked, '1' = not locked)
	  -- control signals
	  FULL_RESET_OUT	: out	std_logic; -- full reset AKA quad_reset
	  LANE_RESET_OUT	: out	std_logic; -- partial reset AKA lane_reset
	  USER_RESET_OUT	: out	std_logic; -- FPGA reset for user logic
	  -- debug signals
	  TIMING_CTR_OUT	: out	std_logic_vector(18 downto 0);
	  BSM_OUT			: out	std_logic_vector(3 downto 0);
	  DEBUG_OUT			: out	std_logic_vector(31 downto 0)
	);
end component;

signal refclkcore			: std_logic;

signal sd_link_ok			: std_logic;
signal sd_link_error		: std_logic_vector(2 downto 0);

signal sd_tx_data			: std_logic_vector(7 downto 0);
signal sd_tx_kcntl			: std_logic;
signal sd_tx_correct_disp	: std_logic;
signal sd_tx_clk			: std_logic;

signal sd_rx_data			: std_logic_vector(7 downto 0);
signal sd_rx_even			: std_logic;
signal sd_rx_kcntl			: std_logic;
signal sd_rx_disp_error		: std_logic;
signal sd_rx_cv_error		: std_logic;
signal sd_rx_clk			: std_logic;

signal pcs_mr_an_complete	: std_logic;
signal pcs_mr_ability		: std_logic_vector(15 downto 0);
signal pcs_mr_page_rx		: std_logic;
signal pcs_mr_reset			: std_logic;

signal pcs_tx_clk_en		: std_logic;
signal pcs_rx_clk_en		: std_logic;
signal pcs_rx_comp_err		: std_logic;

signal pcs_rx_d				: std_logic_vector(7 downto 0);
signal pcs_rx_dv			: std_logic;
signal pcs_rx_er			: std_logic;

signal sd_rx_debug			: std_logic_vector(15 downto 0);
signal sd_tx_debug			: std_logic_vector(15 downto 0);

signal buf_stat_debug		: std_logic_vector(63 downto 0);

signal quad_rst				: std_logic;
signal lane_rst				: std_logic;
signal user_rst				: std_logic;

signal reset_bsm			: std_logic_vector(3 downto 0);
signal reset_debug			: std_logic_vector(31 downto 0);

begin

-- Reset state machine for SerDes
THE_RESET_STATEMACHINE: trb_net16_lsm_sfp_gbe
port map(
	SYSCLK			=> refclkcore,
	RESET			=> '0', -- really?
	CLEAR			=> RESET, -- from 100MHz PLL, includes async part
	-- status signals
	SFP_MISSING_IN		=> SD_PRSNT_N_IN,
	SFP_LOS_IN		=> SD_LOS_IN,
	SD_LINK_OK_IN		=> '1', -- not used
	SD_LOS_IN		=> '0', -- not used
	SD_TXCLK_BAD_IN		=> sd_link_error(2), -- plol
	SD_RXCLK_BAD_IN		=> sd_link_error(1), -- rlol
	-- control signals
	FULL_RESET_OUT		=> quad_rst,
	LANE_RESET_OUT		=> lane_rst,
	USER_RESET_OUT		=> user_rst,
	-- debug signals
	TIMING_CTR_OUT		=> open,
	BSM_OUT			=> reset_bsm,
	DEBUG_OUT		=> reset_debug
);

-- gk 28.04.10
-- SerDes for GbE
clk_int : if (USE_125MHZ_EXTCLK = 0) generate

	refclkcore <= CLK_125_IN;

	SERDES_GBE : serdes_gbe_0_intclock_8b
	port map(
			core_txrefclk            => CLK_125_IN,
			core_rxrefclk            => CLK_125_IN,
		hdinp0                   => SD_RXD_P_IN,
		hdinn0                   => SD_RXD_N_IN,
		hdoutp0                  => SD_TXD_P_OUT,
		hdoutn0                  => SD_TXD_N_OUT,
			ff_rxiclk_ch0            => sd_rx_clk,
			ff_txiclk_ch0            => sd_tx_clk,
			ff_ebrd_clk_0            => sd_rx_clk,
		ff_txdata_ch0            => sd_tx_data,
		ff_rxdata_ch0            => sd_rx_data,
		ff_tx_k_cntrl_ch0        => sd_tx_kcntl,
		ff_rx_k_cntrl_ch0        => sd_rx_kcntl,
			ff_rxfullclk_ch0         => sd_rx_clk,
		ff_xmit_ch0              => '0',
		ff_correct_disp_ch0      => sd_tx_correct_disp,
		ff_disp_err_ch0          => sd_rx_disp_error,
		ff_cv_ch0                => sd_rx_cv_error,
		ff_rx_even_ch0           => sd_rx_even,
		ffc_rrst_ch0             => '0',
		ffc_lane_tx_rst_ch0      => lane_rst,
		ffc_lane_rx_rst_ch0      => lane_rst,
		ffc_txpwdnb_ch0          => '1',
		ffc_rxpwdnb_ch0          => '1',
		ffs_rlos_lo_ch0          => sd_link_error(0),
		ffs_ls_sync_status_ch0   => sd_link_ok,
		ffs_rlol_ch0             => sd_link_error(1),
		oob_out_ch0              => open,
		ffc_macro_rst            => '0',
		ffc_quad_rst             => quad_rst,
		ffc_trst                 => '0',
			ff_txfullclk             => sd_tx_clk,
			ff_txhalfclk             => open,
		ffs_plol                 => sd_link_error(2)
	);
end generate clk_int;

clk_ext : if (USE_125MHZ_EXTCLK = 1) generate
	SERDES_GBE : serdes_gbe_0_extclock_8b                               	        
	port map( -- SerDes connection to outside world
			refclkp					=> SD_REFCLK_P_IN, -- SerDes REFCLK diff. input
			refclkn					=> SD_REFCLK_N_IN,
			hdinp0					=> SD_RXD_P_IN, -- SerDes RX diff. input
			hdinn0					=> SD_RXD_N_IN,
			hdoutp0					=> SD_TXD_P_OUT, -- SerDes TX diff. output
			hdoutn0					=> SD_TXD_N_OUT,
			refck2core				=> refclkcore, -- reference clock from input
			-- RX part
			ff_rxfullclk_ch0			=> sd_rx_clk, -- RX full clock output
			ff_rxiclk_ch0				=> sd_rx_clk,
			ff_ebrd_clk_0				=> sd_rx_clk, -- EB ist not used as recommended by Lattice
			ff_rxdata_ch0				=> sd_rx_data, -- RX data output
			ff_rx_k_cntrl_ch0			=> sd_rx_kcntl, -- RX komma output
			ff_rx_even_ch0			=> sd_rx_even, -- for autonegotiation (output)
			ff_disp_err_ch0			=> sd_rx_disp_error, -- RX disparity error
			ff_cv_ch0					=> sd_rx_cv_error, -- RX code violation error
			-- TX part
			ff_txfullclk				=> sd_tx_clk, -- TX full clock output
			ff_txiclk_ch0				=> sd_tx_clk, 
			ff_txhalfclk				=> open,
			ff_txdata_ch0				=> sd_tx_data, -- TX data input
			ff_tx_k_cntrl_ch0			=> sd_tx_kcntl, -- TX komma input
			ff_xmit_ch0				=> '0', -- for autonegotiation (input)
			ff_correct_disp_ch0		=> sd_tx_correct_disp, -- controls disparity at IPG start (input)
			-- Resets and power down
			ffc_quad_rst				=> quad_rst, -- async reset for whole QUAD (active high)
			ffc_lane_tx_rst_ch0		=> lane_rst, -- async reset for TX channel
			ffc_lane_rx_rst_ch0		=> lane_rst, -- async reset for RX channel
			ffc_rrst_ch0				=> '0', -- '0' for normal operation
			ffc_macro_rst				=> '0', -- '0' for normal operation
			ffc_trst					=> '0', -- '0' for normal operation
			ffc_txpwdnb_ch0			=> '1', -- must be '1'
			ffc_rxpwdnb_ch0			=> '1', -- must be '1'
			-- Status outputs
			ffs_ls_sync_status_ch0	=> sd_link_ok, -- synced to kommas?
			ffs_rlos_lo_ch0			=> sd_link_error(0), -- loss of signal in RX channel
			ffs_rlol_ch0				=> sd_link_error(1), -- loss of lock in RX PLL
			ffs_plol					=> sd_link_error(2), -- loss of lock in TX PLL
			oob_out_ch0				=> open -- not needed
			);
end generate clk_ext;

SD_RX_DATA_PROC: process( sd_rx_clk )
begin
	if( rising_edge(sd_rx_clk) ) then
		sd_rx_debug(15 downto 12) <= (others => '0');
		sd_rx_debug(11)          <= sd_rx_disp_error;
		sd_rx_debug(10)          <= sd_rx_even;
		sd_rx_debug(9)           <= sd_rx_cv_error;
		sd_rx_debug(8)           <= sd_rx_kcntl;
		sd_rx_debug(7 downto 0)  <= sd_rx_data;
	end if;
end process SD_RX_DATA_PROC;

SD_TX_DATA_PROC: process( sd_tx_clk )
begin
	if( rising_edge(sd_tx_clk) ) then
		sd_tx_debug(15 downto 10) <= (others => '0');
		sd_tx_debug(9)            <= sd_tx_correct_disp;
		sd_tx_debug(8)            <= sd_tx_kcntl;
		sd_tx_debug(7 downto 0)   <= sd_tx_data;
	end if;
end process SD_TX_DATA_PROC;

buf_stat_debug(63 downto 40) <= (others => '0');
buf_stat_debug(39 downto 36) <= reset_debug(3 downto 0);
buf_stat_debug(35 downto 32) <= reset_bsm;
-- logic analyzer signals
buf_stat_debug(31)           <= pcs_mr_page_rx;
buf_stat_debug(30)           <= pcs_mr_reset; --pcs_mr_an_complete;
buf_stat_debug(28 downto 26) <= reset_bsm(2 downto 0);
buf_stat_debug(25 downto 23) <= sd_link_error(2 downto 0);
buf_stat_debug(22)           <= sd_link_ok;
buf_stat_debug(21 downto 12) <= sd_tx_debug(9 downto 0);
buf_stat_debug(11 downto 0)  <= sd_rx_debug(11 downto 0);


SGMII_GBE_PCS : sgmii_gbe_pcs32
port map(
	rst_n				=> GSR_N,
	signal_detect			=> sd_link_ok,
	gbe_mode			=> '1',
	sgmii_mode			=> MR_MODE_IN,
	operational_rate		=> "10",
	debug_link_timer_short		=> '0',
	rx_compensation_err		=> pcs_rx_comp_err,
	-- MAC interface
		tx_clk_125			=> refclkcore, -- original clock from SerDes
	tx_clock_enable_source		=> pcs_tx_clk_en,
	tx_clock_enable_sink		=> pcs_tx_clk_en,
	tx_d				=> FT_TXD_IN, -- TX data from MAC
	tx_en				=> FT_TX_EN_IN, -- TX data enable from MAC
	tx_er				=> FT_TX_ER_IN, -- TX error from MAC
		rx_clk_125			=> sd_rx_clk, --refclkcore, -- original clock from SerDes
	rx_clock_enable_source		=> pcs_rx_clk_en,
	rx_clock_enable_sink		=> pcs_rx_clk_en,
	rx_d				=> pcs_rx_d, -- RX data to MAC
	rx_dv				=> pcs_rx_dv, -- RX data enable to MAC
	rx_er				=> pcs_rx_er, -- RX error to MAC
	col				=> FT_COL_OUT,
	crs				=> FT_CRS_OUT,
	-- SerDes interface
	tx_data				=> sd_tx_data, -- TX data to SerDes
	tx_kcntl			=> sd_tx_kcntl, -- TX komma control to SerDes
	tx_disparity_cntl		=> sd_tx_correct_disp, -- idle parity state control in IPG (to SerDes)
		serdes_recovered_clk		=> sd_rx_clk, -- 125MHz recovered from receive bit stream
	rx_data				=> sd_rx_data, -- RX data from SerDes
	rx_kcntl			=> sd_rx_kcntl, -- RX komma control from SerDes
	rx_err_decode_mode		=> '0', -- receive error control mode fixed to normal
	rx_even				=> '0', -- unused (receive error control mode = normal, tie to GND)
	rx_disp_err			=> sd_rx_disp_error, -- RX disparity error from SerDes
	rx_cv_err			=> sd_rx_cv_error, -- RX code violation error from SerDes
	-- Autonegotiation stuff
	mr_an_complete			=> pcs_mr_an_complete,
	mr_page_rx			=> pcs_mr_page_rx,
	mr_lp_adv_ability		=> pcs_mr_ability,
	mr_main_reset			=> pcs_mr_reset,
	mr_an_enable			=> MR_AN_ENABLE_IN,
	mr_restart_an			=> MR_RESTART_AN_IN,
	mr_adv_ability			=> MR_ADV_ABILITY_IN
);

SYNC_RX_PROC : process(sd_rx_clk)
begin
  if rising_edge(sd_rx_clk) then
    FT_RXD_OUT   <= pcs_rx_d;
    FT_RX_EN_OUT <= pcs_rx_dv;
    FT_RX_ER_OUT <= pcs_rx_er;
  end if;
end process SYNC_RX_PROC;

pcs_mr_reset <= MR_RESET_IN or RESET or user_rst;

FT_TX_CLK_EN_OUT     <= pcs_tx_clk_en; -- to MAC
FT_RX_CLK_EN_OUT     <= pcs_rx_clk_en; -- to MAC

MR_AN_LP_ABILITY_OUT <= pcs_mr_ability;
MR_AN_COMPLETE_OUT   <= pcs_mr_an_complete;
MR_AN_PAGE_RX_OUT    <= pcs_mr_page_rx;

-- Clock games
CLK_125_OUT    <= refclkcore;
CLK_125_RX_OUT <= sd_rx_clk;

-- Fakes
STAT_OP       <= (others => '0');
SD_TXDIS_OUT  <= '0'; -- enable 
STAT_DEBUG    <= buf_stat_debug;

end architecture;