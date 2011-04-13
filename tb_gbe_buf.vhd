LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.math_real.all;
USE ieee.numeric_std.ALL;

ENTITY testbench IS
END testbench;

ARCHITECTURE behavior OF testbench IS 
	component trb_net16_gbe_buf is
	generic( 
		DO_SIMULATION		: integer range 0 to 1 := 1;
		USE_125MHZ_EXTCLK       : integer range 0 to 1 := 1
	);
	port(
			CLK							: in	std_logic;
	TEST_CLK					: in	std_logic; -- only for simulation!
	CLK_125_IN				: in std_logic;  -- gk 28.04.01 used only in internal 125MHz clock mode
RESET : IN std_logic;
		GSR_N : IN std_logic;
		STAGE_CTRL_REGS_IN : IN std_logic_vector(31 downto 0);
		------------------------
		IP_CFG_START_IN : IN std_logic;
		IP_CFG_BANK_SEL_IN : IN std_logic_vector(3 downto 0);
		IP_CFG_MEM_DATA_IN : IN std_logic_vector(31 downto 0);
		MR_RESET_IN : IN std_logic;
		MR_MODE_IN : IN std_logic;
		MR_RESTART_IN : IN std_logic;
		IP_CFG_MEM_CLK_OUT : OUT std_logic;
		IP_CFG_DONE_OUT : OUT std_logic;
		IP_CFG_MEM_ADDR_OUT : OUT std_logic_vector(7 downto 0);
		-- gk 29.03.10
		SLV_ADDR_IN                  : in std_logic_vector(7 downto 0);
		SLV_READ_IN                  : in std_logic;
		SLV_WRITE_IN                 : in std_logic;
		SLV_BUSY_OUT                 : out std_logic;
		SLV_ACK_OUT                  : out std_logic;
		SLV_DATA_IN                  : in std_logic_vector(31 downto 0);
		SLV_DATA_OUT                 : out std_logic_vector(31 downto 0);
		-- gk 26.04.10
		-- registers setup interface
		BUS_ADDR_IN               : in std_logic_vector(7 downto 0);
		BUS_DATA_IN               : in std_logic_vector(31 downto 0);
		BUS_DATA_OUT              : out std_logic_vector(31 downto 0);  -- gk 26.04.10
		BUS_WRITE_EN_IN           : in std_logic;  -- gk 26.04.10
		BUS_READ_EN_IN            : in std_logic;  -- gk 26.04.10
		BUS_ACK_OUT               : out std_logic;  -- gk 26.04.10
		-- gk 23.04.10
		LED_PACKET_SENT_OUT        : out std_logic;
		LED_AN_DONE_N_OUT            : out std_logic;
		------------------------
		CTS_NUMBER_IN : IN std_logic_vector(15 downto 0);
		CTS_CODE_IN : IN std_logic_vector(7 downto 0);
		CTS_INFORMATION_IN : IN std_logic_vector(7 downto 0);
		CTS_READOUT_TYPE_IN : IN std_logic_vector(3 downto 0);
		CTS_START_READOUT_IN : IN std_logic;
		CTS_READ_IN : IN std_logic;
		FEE_DATA_IN : IN std_logic_vector(15 downto 0);
		FEE_DATAREADY_IN : IN std_logic;
		FEE_STATUS_BITS_IN : IN std_logic_vector(31 downto 0);
		FEE_BUSY_IN : IN std_logic;
		SFP_RXD_P_IN : IN std_logic;
		SFP_RXD_N_IN : IN std_logic;
		SFP_REFCLK_P_IN : IN std_logic;
		SFP_REFCLK_N_IN : IN std_logic;
		SFP_PRSNT_N_IN : IN std_logic;
		SFP_LOS_IN : IN std_logic;          
		STAGE_STAT_REGS_OUT : OUT std_logic_vector(31 downto 0);
		CTS_DATA_OUT : OUT std_logic_vector(31 downto 0);
		CTS_DATAREADY_OUT : OUT std_logic;
		CTS_READOUT_FINISHED_OUT : OUT std_logic;
		CTS_LENGTH_OUT : OUT std_logic_vector(15 downto 0);
		CTS_ERROR_PATTERN_OUT : OUT std_logic_vector(31 downto 0);
		FEE_READ_OUT : OUT std_logic;
		SFP_TXD_P_OUT : OUT std_logic;
		SFP_TXD_N_OUT : OUT std_logic;
		SFP_TXDIS_OUT : OUT std_logic;
			-- for simulation of receiving part only
	MAC_RX_EOF_IN		: in	std_logic;
	MAC_RXD_IN		: in	std_logic_vector(7 downto 0);
	MAC_RX_EN_IN		: in	std_logic;

		ANALYZER_DEBUG_OUT : OUT std_logic_vector(63 downto 0)
		);
	END COMPONENT;

	SIGNAL CLK :  std_logic;
	SIGNAL TEST_CLK :  std_logic;
	SIGNAL RESET :  std_logic;
	SIGNAL GSR_N :  std_logic;
	SIGNAL STAGE_STAT_REGS_OUT :  std_logic_vector(31 downto 0);
	SIGNAL STAGE_CTRL_REGS_IN :  std_logic_vector(31 downto 0);
	SIGNAL IP_CFG_START_IN :  std_logic;
	SIGNAL IP_CFG_BANK_SEL_IN :  std_logic_vector(3 downto 0);
	SIGNAL IP_CFG_MEM_DATA_IN :  std_logic_vector(31 downto 0);
	SIGNAL MR_RESET_IN :  std_logic;
	SIGNAL MR_MODE_IN :  std_logic;
	SIGNAL MR_RESTART_IN :  std_logic;
	SIGNAL IP_CFG_MEM_CLK_OUT :  std_logic;
	SIGNAL IP_CFG_DONE_OUT :  std_logic;
	SIGNAL IP_CFG_MEM_ADDR_OUT :  std_logic_vector(7 downto 0);
	SIGNAL CTS_NUMBER_IN :  std_logic_vector(15 downto 0);
	SIGNAL CTS_CODE_IN :  std_logic_vector(7 downto 0);
	SIGNAL CTS_INFORMATION_IN :  std_logic_vector(7 downto 0);
	SIGNAL CTS_READOUT_TYPE_IN :  std_logic_vector(3 downto 0);
	SIGNAL CTS_START_READOUT_IN :  std_logic;
	SIGNAL CTS_DATA_OUT :  std_logic_vector(31 downto 0);
	SIGNAL CTS_DATAREADY_OUT :  std_logic;
	SIGNAL CTS_READOUT_FINISHED_OUT :  std_logic;
	SIGNAL CTS_READ_IN :  std_logic;
	SIGNAL CTS_LENGTH_OUT :  std_logic_vector(15 downto 0);
	SIGNAL CTS_ERROR_PATTERN_OUT :  std_logic_vector(31 downto 0);
	SIGNAL FEE_DATA_IN :  std_logic_vector(15 downto 0);
	SIGNAL FEE_DATAREADY_IN :  std_logic;
	SIGNAL FEE_READ_OUT :  std_logic;
	SIGNAL FEE_STATUS_BITS_IN :  std_logic_vector(31 downto 0);
	SIGNAL FEE_BUSY_IN :  std_logic;
	SIGNAL SFP_RXD_P_IN :  std_logic;
	SIGNAL SFP_RXD_N_IN :  std_logic;
	SIGNAL SFP_TXD_P_OUT :  std_logic;
	SIGNAL SFP_TXD_N_OUT :  std_logic;
	SIGNAL SFP_REFCLK_P_IN :  std_logic;
	SIGNAL SFP_REFCLK_N_IN :  std_logic;
	SIGNAL SFP_PRSNT_N_IN :  std_logic;
	SIGNAL SFP_LOS_IN :  std_logic;
	SIGNAL SFP_TXDIS_OUT :  std_logic;
	SIGNAL ANALYZER_DEBUG_OUT :  std_logic_vector(63 downto 0);
	--gk 29.03.10
	signal SLV_ADDR_IN : std_logic_vector(7 downto 0);
	signal SLV_READ_IN : std_logic;
	signal SLV_WRITE_IN : std_logic;
	signal SLV_BUSY_OUT : std_logic;
	signal SLV_ACK_OUT : std_logic;
	signal SLV_DATA_IN : std_logic_vector(31 downto 0);
	signal SLV_DATA_OUT : std_logic_vector(31 downto 0);
	-- for simulation of receiving part only
	signal MAC_RX_EOF_IN		:	std_logic;
	signal MAC_RXD_IN		:	std_logic_vector(7 downto 0);
	signal MAC_RX_EN_IN		:	std_logic;

BEGIN

-- Please check and add your generic clause manually
	uut: trb_net16_gbe_buf
	GENERIC MAP( DO_SIMULATION => 1, USE_125MHZ_EXTCLK => 1 )
	PORT MAP(
		CLK => CLK,
		CLK_125_IN => '0',
		TEST_CLK => TEST_CLK,
		RESET => RESET,
		GSR_N => GSR_N,
		STAGE_STAT_REGS_OUT => STAGE_STAT_REGS_OUT,
		STAGE_CTRL_REGS_IN => STAGE_CTRL_REGS_IN,
		IP_CFG_START_IN => IP_CFG_START_IN,
		IP_CFG_BANK_SEL_IN => IP_CFG_BANK_SEL_IN,
		IP_CFG_MEM_DATA_IN => IP_CFG_MEM_DATA_IN,
		MR_RESET_IN => MR_RESET_IN,
		MR_MODE_IN => MR_MODE_IN,
		MR_RESTART_IN => MR_RESTART_IN,
		IP_CFG_MEM_CLK_OUT => IP_CFG_MEM_CLK_OUT,
		IP_CFG_DONE_OUT => IP_CFG_DONE_OUT,
		IP_CFG_MEM_ADDR_OUT => IP_CFG_MEM_ADDR_OUT,
		-- gk 29.03.10
		SLV_ADDR_IN => SLV_ADDR_IN,
		SLV_READ_IN => SLV_READ_IN,
		SLV_WRITE_IN => SLV_WRITE_IN,
		SLV_BUSY_OUT => SLV_BUSY_OUT,
		SLV_ACK_OUT => SLV_ACK_OUT,
		SLV_DATA_IN => SLV_DATA_IN,
		SLV_DATA_OUT => SLV_DATA_OUT,
		-- gk 22.04.10
		-- registers setup interface
		BUS_ADDR_IN => x"00",
		BUS_DATA_IN => x"0000_0000",
		BUS_DATA_OUT => open,
		BUS_WRITE_EN_IN => '0',
		BUS_READ_EN_IN => '0',
		BUS_ACK_OUT => open,
		-- gk 23.04.10
		LED_PACKET_SENT_OUT => open,
		LED_AN_DONE_N_OUT => open,
		--------------------------
		CTS_NUMBER_IN => CTS_NUMBER_IN,
		CTS_CODE_IN => CTS_CODE_IN,
		CTS_INFORMATION_IN => CTS_INFORMATION_IN,
		CTS_READOUT_TYPE_IN => CTS_READOUT_TYPE_IN,
		CTS_START_READOUT_IN => CTS_START_READOUT_IN,
		CTS_DATA_OUT => CTS_DATA_OUT,
		CTS_DATAREADY_OUT => CTS_DATAREADY_OUT,
		CTS_READOUT_FINISHED_OUT => CTS_READOUT_FINISHED_OUT,
		CTS_READ_IN => CTS_READ_IN,
		CTS_LENGTH_OUT => CTS_LENGTH_OUT,
		CTS_ERROR_PATTERN_OUT => CTS_ERROR_PATTERN_OUT,
		FEE_DATA_IN => FEE_DATA_IN,
		FEE_DATAREADY_IN => FEE_DATAREADY_IN,
		FEE_READ_OUT => FEE_READ_OUT,
		FEE_STATUS_BITS_IN => FEE_STATUS_BITS_IN,
		FEE_BUSY_IN => FEE_BUSY_IN,
		SFP_RXD_P_IN => SFP_RXD_P_IN,
		SFP_RXD_N_IN => SFP_RXD_N_IN,
		SFP_TXD_P_OUT => SFP_TXD_P_OUT,
		SFP_TXD_N_OUT => SFP_TXD_N_OUT,
		SFP_REFCLK_P_IN => SFP_REFCLK_P_IN,
		SFP_REFCLK_N_IN => SFP_REFCLK_N_IN,
		SFP_PRSNT_N_IN => SFP_PRSNT_N_IN,
		SFP_LOS_IN => SFP_LOS_IN,
		SFP_TXDIS_OUT => SFP_TXDIS_OUT,
	-- for simulation of receiving part only
	MAC_RX_EOF_IN		=> MAC_RX_EOF_IN,
	MAC_RXD_IN		=> MAC_RXD_IN,
	MAC_RX_EN_IN		=> MAC_RX_EN_IN,
		ANALYZER_DEBUG_OUT => ANALYZER_DEBUG_OUT
	);



-- 100 MHz system clock
CLOCK_GEN_PROC: process
begin
	clk <= '1'; wait for 5.0 ns;
	clk <= '0'; wait for 5.0 ns;
end process CLOCK_GEN_PROC;

-- 125 MHz MAC clock
CLOCK2_GEN_PROC: process
begin
	test_clk <= '1'; wait for 4.0 ns;
	test_clk <= '0'; wait for 3.0 ns;
end process CLOCK2_GEN_PROC;

-- Testbench
TESTBENCH_PROC: process
-- test data from TRBnet
variable test_data_len : integer range 0 to 65535 := 1;
variable test_loop_len : integer range 0 to 65535 := 0;
variable test_hdr_len : unsigned(15 downto 0) := x"0000";
variable test_evt_len : unsigned(15 downto 0) := x"0000";
variable test_data : unsigned(15 downto 0) := x"ffff";
variable test_data2 : unsigned(7 downto 0) := x"ff";

variable trigger_counter : unsigned(15 downto 0) := x"4710";
variable trigger_loop : integer range 0 to 65535 := 15;

-- 1400 bytes MTU => 350 as limit for fragmentation
variable max_event_size : real := 512.0;

variable seed1 : positive; -- seed for random generator
variable seed2 : positive; -- seed for random generator
variable rand : real; -- random value (0.0 ... 1.0)
variable int_rand : integer; -- random value, scaled to your needs
variable cts_random_number : std_logic_vector(7 downto 0);

variable stim : std_logic_vector(15 downto 0);


-- RND test
--UNIFORM(seed1, seed2, rand);
--int_rand := INTEGER(TRUNC(rand*65536.0));
--stim := std_logic_vector(to_unsigned(int_rand, stim'LENGTH));

begin
	-- Setup signals
	reset <= '0';
	gsr_n <= '1';
	
	stage_ctrl_regs_in <= x"0000_0000";
	
	--ip_cfg_start_in <= '0';
	--ip_cfg_bank_sel_in <= x"0";
	--ip_cfg_mem_data_in <= x"0000_0000";
	mr_reset_in <= '0';
	mr_mode_in <= '0';
	mr_restart_in <= '0';
	SLV_ADDR_IN <= x"00";
	SLV_READ_IN <= '0';
	SLV_WRITE_IN <= '0';
	SLV_DATA_IN <= x"0000_0000";
	
	sfp_los_in <= '0'; -- signal from SFP is present
	sfp_prsnt_n_in <= '0'; -- SFP itself is present
	sfp_refclk_n_in <= '0';
	sfp_refclk_p_in <= '1';
	
	cts_number_in <= x"0000";
	cts_code_in <= x"00";
	cts_information_in <= x"00";
	cts_readout_type_in <= x"0";
	cts_start_readout_in <= '0';
	cts_read_in <= '0';
	
	fee_data_in <= x"0000";
	fee_dataready_in <= '0';
	fee_status_bits_in <= x"1234_5678";
	fee_busy_in <= '0';
	
	MAC_RX_EN_IN <= '0';
	MAC_RX_EOF_IN <= '0';
	MAC_RXD_IN <= (others => '0');


	wait for 22 ns;
	
	-- Reset the whole stuff
	wait until rising_edge(clk);
	reset <= '1';
	gsr_n <= '0';
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	reset <= '0';
	gsr_n <= '1';
	wait until rising_edge(clk);
	--wait for 100 ns;
	
	-- Tests may start here
--	wait until ft_bsm_init_tst = x"7";

	--ip_cfg_start_in <= '1';

	wait for 500 ns;


-------------------------------------------------------------------------------
-- Loop the transmissions
-------------------------------------------------------------------------------
	trigger_counter := x"4710";
	trigger_loop    := 10;

	RECEIVE_LOOP: for J in 0 to 1 loop

		wait for 200 ns;
	
		-- IPU transmission starts
		wait until rising_edge(test_clk);
		
		test_data2     := x"ff";
		MY_DATA_LOOP2: for k in 0 to 200 + (J * 10) loop
			test_data2 := test_data2 + 1;
			wait until rising_edge(test_clk);
			MAC_RXD_IN <= std_logic_vector(test_data2); 
			MAC_RX_EN_IN <= '1';
		end loop MY_DATA_LOOP2;

		MAC_RX_EN_IN <= '0';
		MAC_RXD_IN <= "00000000";
		MAC_RX_EOF_IN <= '1';
		wait until rising_edge(test_clk);
		MAC_RX_EOF_IN <= '0';

		--wait for 3 us;

	end loop RECEIVE_LOOP;

	MY_TRIGGER_LOOP: for J in 0 to trigger_loop loop
		-- generate a real random byte for CTS
		UNIFORM(seed1, seed2, rand);
		int_rand := INTEGER(TRUNC(rand*256.0));
		cts_random_number := std_logic_vector(to_unsigned(int_rand, cts_random_number'LENGTH));
	
		-- IPU transmission starts
		wait until rising_edge(clk);
		cts_number_in <= std_logic_vector( trigger_counter );
		cts_code_in <= cts_random_number;
		cts_information_in <= x"d2"; -- cts_information_in <= x"de"; -- gk 29.03.10
		cts_readout_type_in <= x"1";
		cts_start_readout_in <= '1';
		wait until rising_edge(clk);
		wait for 400 ns;

		wait until rising_edge(clk);
		fee_busy_in <= '1';
		wait for 300 ns;
		wait until rising_edge(clk);

		-- ONE DATA TRANSMISSION
		-- dice a length
		UNIFORM(seed1, seed2, rand);
		--test_data_len := INTEGER(TRUNC(rand * 800.0)) + 1;
		
		--test_data_len := 9685;
		test_data_len := 400;
		
		-- calculate the needed variables
		test_loop_len := 2*(test_data_len - 1) + 1;
		test_hdr_len := to_unsigned( test_data_len + 1, 16 );
		test_evt_len := to_unsigned( test_data_len, 16 );

		-- original data block (trigger 1, random 0xaa, number 0x4711, source 0x21)
		fee_dataready_in <= '1';
		fee_data_in <= x"10" & cts_random_number;
		wait until rising_edge(clk) and (fee_read_out = '1'); -- transfer of first data word
		fee_dataready_in <= '0';
		wait until rising_edge(clk); -- BLA
		wait until rising_edge(clk); -- BLA
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		fee_dataready_in <= '1';
		fee_data_in <= std_logic_vector( trigger_counter );
		wait until rising_edge(clk) and (fee_read_out = '1'); -- transfer of second data word
		fee_dataready_in <= '0';
		wait until rising_edge(clk); -- BLA
		wait until rising_edge(clk); -- BLA
		wait until rising_edge(clk); -- BLA
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		fee_dataready_in <= '1';
		fee_data_in <= std_logic_vector( test_hdr_len );
		wait until rising_edge(clk) and (fee_read_out = '1'); -- transfer of third data word
		fee_data_in <= x"ff21";
		wait until rising_edge(clk) and (fee_read_out = '1'); -- transfer of fourth data word
		fee_dataready_in <= '0';
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		fee_dataready_in <= '1';
		fee_data_in <= std_logic_vector( test_evt_len );
		wait until rising_edge(clk) and (fee_read_out = '1');
		fee_data_in <= x"ff22";	
		wait until rising_edge(clk) and (fee_read_out = '1');
		fee_dataready_in <= '0';
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);

		test_data     := x"ffff";
		MY_DATA_LOOP: for J in 0 to test_loop_len loop
			test_data := test_data + 1;
			wait until rising_edge(clk);
			fee_data_in <= std_logic_vector(test_data); 
			if( (test_data MOD 5) = 0 ) then
				fee_dataready_in <= '0';
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				fee_dataready_in <= '1';
			else
				fee_dataready_in <= '1';
			end if;
 				--fee_dataready_in <= '1';
		end loop MY_DATA_LOOP;
		-- there must be padding words to get multiple of four LWs
	
		wait until rising_edge(clk);
		fee_dataready_in <= '0';
		fee_data_in <= x"0000";	

		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		fee_busy_in <= '0';


		trigger_loop    := trigger_loop + 1;
		trigger_counter := trigger_counter + 1;

		wait until rising_edge(clk);
		wait until rising_edge(clk);
		cts_read_in <= '1';
		wait until rising_edge(clk);
		cts_read_in <= '0';
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		cts_start_readout_in <= '0';
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);	
		
		--wait for 8 us;

	end loop MY_TRIGGER_LOOP;









--	wait for 8 us;
-------------------------------------------------------------------------------
-- end of loop
-------------------------------------------------------------------------------
	-- Stay a while... stay forever!!!
	wait;	
	
end process TESTBENCH_PROC;

END;

