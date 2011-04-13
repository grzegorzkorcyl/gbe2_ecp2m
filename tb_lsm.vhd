LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY testbench IS
END testbench;

ARCHITECTURE behavior OF testbench IS 

	COMPONENT trb_net16_lsm_sfp_gbe
	PORT(
		SYSCLK : IN std_logic;
		RESET : IN std_logic;
		CLEAR : IN std_logic;
		SFP_MISSING_IN : IN std_logic;
		SFP_LOS_IN : IN std_logic;
		SD_LINK_OK_IN : IN std_logic;
		SD_LOS_IN : IN std_logic;
		SD_TXCLK_BAD_IN : IN std_logic;
		SD_RXCLK_BAD_IN : IN std_logic;          
		FULL_RESET_OUT : OUT std_logic;
		LANE_RESET_OUT : OUT std_logic;
		USER_RESET_OUT : OUT std_logic;
		TIMING_CTR_OUT : OUT std_logic_vector(18 downto 0);
		BSM_OUT : OUT std_logic_vector(3 downto 0);
		DEBUG_OUT : OUT std_logic_vector(31 downto 0)
		);
	END COMPONENT;

	SIGNAL SYSCLK :  std_logic;
	SIGNAL RESET :  std_logic;
	SIGNAL CLEAR :  std_logic;
	SIGNAL SFP_MISSING_IN :  std_logic;
	SIGNAL SFP_LOS_IN :  std_logic;
	SIGNAL SD_LINK_OK_IN :  std_logic;
	SIGNAL SD_LOS_IN :  std_logic;
	SIGNAL SD_TXCLK_BAD_IN :  std_logic;
	SIGNAL SD_RXCLK_BAD_IN :  std_logic;
	SIGNAL FULL_RESET_OUT :  std_logic;
	SIGNAL LANE_RESET_OUT :  std_logic;
	SIGNAL USER_RESET_OUT :  std_logic;
	SIGNAL TIMING_CTR_OUT :  std_logic_vector(18 downto 0);
	SIGNAL BSM_OUT :  std_logic_vector(3 downto 0);
	SIGNAL DEBUG_OUT :  std_logic_vector(31 downto 0);

BEGIN

-- Please check and add your generic clause manually
	uut: trb_net16_lsm_sfp_gbe PORT MAP(
		SYSCLK => SYSCLK,
		RESET => RESET,
		CLEAR => CLEAR,
		SFP_MISSING_IN => SFP_MISSING_IN,
		SFP_LOS_IN => SFP_LOS_IN,
		SD_LINK_OK_IN => SD_LINK_OK_IN,
		SD_LOS_IN => SD_LOS_IN,
		SD_TXCLK_BAD_IN => SD_TXCLK_BAD_IN,
		SD_RXCLK_BAD_IN => SD_RXCLK_BAD_IN,
		FULL_RESET_OUT => FULL_RESET_OUT,
		LANE_RESET_OUT => LANE_RESET_OUT,
		USER_RESET_OUT => USER_RESET_OUT,
		TIMING_CTR_OUT => TIMING_CTR_OUT,
		BSM_OUT => BSM_OUT,
		DEBUG_OUT => DEBUG_OUT
	);
                         

CLOCK_GEN: process
begin
	sysclk <= '1'; wait for 4.0 ns;
	sysclk <= '0'; wait for 4.0 ns;
end process CLOCK_GEN;

THE_TESTBENCH: process
begin
	-- Setup signals
	reset <= '0';
	clear <= '0';
	sfp_missing_in <= '0';
	sfp_los_in <= '0';
	sd_link_ok_in <= '0';
	sd_los_in <= '0';
	sd_txclk_bad_in <= '1';
	sd_rxclk_bad_in <= '1';
	wait for 100 ns;
	
	-- Reset
	clear <= '1';
	wait for 100 ns;
	clear <= '0';
	wait for 10 ns;
	
	-- Tests may start now
	wait until falling_edge(full_reset_out);
	wait for 123 ns;
	sd_txclk_bad_in <= '0';
	wait for 433 ns;
	sd_rxclk_bad_in <= '0';

	wait for 1.1 us;
	sd_rxclk_bad_in <= '1';
	wait for 33 ns;
	sd_rxclk_bad_in <= '0';

	
	wait until rising_edge(sysclk);	
	
	-- Stay a while.... stay forever!!! Muahahaha!!!!
	wait;

end process THE_TESTBENCH;
                                                             
END;                                                         