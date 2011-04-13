-- LinkStateMachine for SFPs (GigE)

-- Still missing: link reset features, fifo full error handling, signals on stat_op
-- Take care: all input signals must be synchronous to SYSCLK,
--            all output signals are synchronous to SYSCLK.
-- Clock Domain Crossing is in your responsibility!

LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.std_logic_ARITH.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
--use work.trb_net_std.all;

entity trb_net16_lsm_sfp_gbe is
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
end entity;

architecture lsm_sfp_gbe of trb_net16_lsm_sfp_gbe is

-- state machine signals
type STATES is ( QRST, SLEEP, DELAY, USERRST, LINK );
signal CURRENT_STATE, NEXT_STATE: STATES;

signal state_bits			: std_logic_vector(3 downto 0);
signal next_ce_tctr			: std_logic;
signal ce_tctr				: std_logic;
signal next_rst_tctr		: std_logic;
signal rst_tctr				: std_logic;
signal next_quad_rst		: std_logic;
signal quad_rst				: std_logic;
signal next_lane_rst		: std_logic;
signal lane_rst				: std_logic;
signal next_user_rst		: std_logic;
signal user_rst				: std_logic;
signal sfp_missing_q		: std_logic;
signal sfp_missing_qq		: std_logic;
signal sfp_los_q			: std_logic;
signal sfp_los_qq			: std_logic;
signal sd_rxclk_bad_q		: std_logic;
signal sd_rxclk_bad_qq		: std_logic;
signal sd_rxclk_bad_qqq		: std_logic;
signal sd_txclk_bad_q		: std_logic;
signal sd_txclk_bad_qq		: std_logic;
signal sd_txclk_bad_qqq		: std_logic;
signal sd_rxclk_warn_comb	: std_logic;
signal sd_rxclk_warn		: std_logic; -- rising edge on rlol detected
signal sd_txclk_warn_comb	: std_logic;
signal sd_txclk_warn		: std_logic; -- rising edge on plol detected
signal timing_ctr			: std_logic_vector(18 downto 0);
signal debug				: std_logic_vector(31 downto 0);

begin

-- Debug signals
debug(31 downto 4)   <= (others => '0');
debug(3)             <= sd_txclk_warn;
debug(2)             <= sd_rxclk_warn;
debug(1)             <= rst_tctr;
debug(0)             <= ce_tctr;

-- synchronize external signals from SFP
THE_SYNC_PROC: process( sysclk )
begin
	if( rising_edge(sysclk) ) then
		-- SFP input signals
		sfp_missing_qq   <= sfp_missing_q;
		sfp_missing_q    <= sfp_missing_in;
		sfp_los_qq       <= sfp_los_q;
		sfp_los_q        <= sfp_los_in;
		-- SerDes input signals
		sd_rxclk_bad_qqq <= sd_rxclk_bad_qq;
		sd_rxclk_bad_qq  <= sd_rxclk_bad_q;
		sd_rxclk_bad_q   <= sd_rxclk_bad_in;
		sd_txclk_bad_qqq <= sd_txclk_bad_q;
		sd_txclk_bad_qq  <= sd_txclk_bad_q;
		sd_txclk_bad_q   <= sd_txclk_bad_in;
		-- edge detectors
		sd_rxclk_warn    <= sd_rxclk_warn_comb;
		sd_txclk_warn    <= sd_txclk_warn_comb;
	end if;
end process THE_SYNC_PROC;

-- combinatorial part of edge detectors (rlol, see remark on page 8-63 in HB1003.pdf)
sd_rxclk_warn_comb <= '1' when ( (sd_rxclk_bad_qqq = '0') and (sd_rxclk_bad_qq = '1') ) else '0';
sd_txclk_warn_comb <= '1' when ( (sd_txclk_bad_qqq = '0') and (sd_txclk_bad_qq = '1') ) else '0';

--------------------------------------------------------------------------
-- Main control state machine, startup control for SFP
--------------------------------------------------------------------------

-- Timing counter for reset sequencing
THE_TIMING_COUNTER_PROC: process( sysclk, clear )
begin
	if( clear = '1' ) then
		timing_ctr <= (others => '0');
	elsif( rising_edge(sysclk) ) then
		if   ( (rst_tctr = '1') or (sd_rxclk_warn = '1') or (sd_txclk_warn = '1') ) then
			timing_ctr <= (others => '0');
		elsif( ce_tctr = '1' ) then
			timing_ctr <= timing_ctr + 1;
		end if;
	end if;
end process THE_TIMING_COUNTER_PROC;

-- State machine
-- state registers
STATE_MEM: process( sysclk, clear )
begin
	if( clear = '1' ) then
		CURRENT_STATE  <= QRST;
		ce_tctr        <= '0';
		rst_tctr       <= '0';
		quad_rst       <= '1';
		lane_rst       <= '1';
		user_rst       <= '1';
	elsif( rising_edge(sysclk) ) then
		CURRENT_STATE  <= NEXT_STATE;
		ce_tctr        <= next_ce_tctr;
		rst_tctr       <= next_rst_tctr;
		quad_rst       <= next_quad_rst;
		lane_rst       <= next_lane_rst;
		user_rst       <= next_user_rst;
	end if;
end process STATE_MEM;

-- state transitions
PROC_STATE_TRANSFORM: process( CURRENT_STATE, sfp_missing_qq, sfp_los_qq, sd_txclk_bad_qqq, sd_rxclk_bad_qqq,
                               timing_ctr(8), timing_ctr(18), timing_ctr(17),
                               reset )
begin
	NEXT_STATE     <= QRST; -- avoid latches
	next_ce_tctr   <= '0';
	next_rst_tctr  <= '0';
	next_quad_rst  <= '0';
	next_lane_rst  <= '0';
	next_user_rst  <= '0';
	case CURRENT_STATE is
		when QRST =>  -- initial state, we stay there unless CLEAR is deasserted.
			state_bits <= x"0";
			if( (timing_ctr(8) = '1') ) then
				NEXT_STATE    <= SLEEP; -- release QUAD_RST, wait for lock of RxClock and TxClock
				next_lane_rst <= '1';
				next_user_rst <= '1';
				next_rst_tctr <= '1';
			else
				NEXT_STATE    <= QRST; -- count delay
				next_ce_tctr  <= '1';
				next_quad_rst <= '1';
				next_lane_rst <= '1';
				next_user_rst <= '1';
			end if;
		when SLEEP => -- we check for SFP presence and signal
			state_bits <= x"1";
			if( (sfp_missing_qq = '0') and (sfp_los_qq = '0') ) then
				NEXT_STATE    <= DELAY; -- do a correctly timed QUAD reset (about 150ns)
				next_ce_tctr  <= '1';
				next_lane_rst <= '1';
				next_user_rst <= '1';
			else
				NEXT_STATE    <= SLEEP; -- wait for SFP present signal
				next_lane_rst <= '1';
				next_user_rst <= '1';
			end if;
		when DELAY => -- we wait approx. 4ms and check for PLL lock in the SerDes
			state_bits <= x"2";
			if( (timing_ctr(18) = '1') and (timing_ctr(17) = '1') and (sd_rxclk_bad_qqq = '0') and (sd_txclk_bad_qqq = '0') ) then
				NEXT_STATE    <= USERRST; -- we release lane reset
				next_ce_tctr  <= '1';
				next_user_rst <= '1';
			else
				NEXT_STATE    <= DELAY;
				next_ce_tctr  <= '1';
				next_lane_rst <= '1';
				next_user_rst <= '1';
			end if;
		when USERRST => -- short delay for user reset
			state_bits <= x"3";
			if( (timing_ctr(18) = '0') and (timing_ctr(17) = '0') ) then
				NEXT_STATE    <= LINK;
				next_rst_tctr <= '1';
			else
				NEXT_STATE    <= USERRST;
				next_ce_tctr  <= '1';
				next_user_rst <= '1';
			end if;
		when LINK => -- operational
			state_bits <= x"4";
			NEXT_STATE <= LINK;
		when others => 
			NEXT_STATE <= QRST;
	end case;
  
	-- emergency jumps in case of SFP problems
	if( ((sfp_missing_qq = '1') or (sfp_los_qq = '1') or (RESET = '1')) and CURRENT_STATE /= QRST ) then
		NEXT_STATE    <= SLEEP; -- wait for SFP present signal
		next_rst_tctr <= '1';
		next_lane_rst <= '1';
		next_user_rst <= '1';
	end if;
end process;

--------------------------------------------------------------------------
-- Output signals
--------------------------------------------------------------------------
full_reset_out  <= quad_rst;
lane_reset_out  <= lane_rst;
user_reset_out  <= user_rst;

--------------------------------------------------------------------------
-- Debug output
--------------------------------------------------------------------------
timing_ctr_out  <= timing_ctr;
bsm_out         <= state_bits;
debug_out       <= debug;

end architecture;