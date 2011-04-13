LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.math_real.all;
USE ieee.numeric_std.ALL;

ENTITY testbench IS
END testbench;

ARCHITECTURE behavior OF testbench IS 

	COMPONENT trb_net16_ipu2gbe
	PORT(
		CLK : IN std_logic;
		RESET : IN std_logic;
		START_CONFIG_OUT : OUT std_logic;
		BANK_SELECT_OUT : OUT std_logic_vector(3 downto 0);
		CONFIG_DONE_IN : IN std_logic;
		DATA_GBE_ENABLE_IN : IN std_logic;
		DATA_IPU_ENABLE_IN : IN std_logic;
		MULTI_EVT_ENABLE_IN : IN std_logic;
		CTS_NUMBER_IN : IN std_logic_vector(15 downto 0);
		CTS_CODE_IN : IN std_logic_vector(7 downto 0);
		CTS_INFORMATION_IN : IN std_logic_vector(7 downto 0);
		CTS_READOUT_TYPE_IN : IN std_logic_vector(3 downto 0);
		CTS_START_READOUT_IN : IN std_logic;
		CTS_READ_IN : IN std_logic;
		FEE_DATA_IN : IN std_logic_vector(15 downto 0);
		FEE_DATAREADY_IN : IN std_logic;
		FEE_BUSY_IN : IN std_logic;
		FEE_STATUS_BITS_IN : IN std_logic_vector(31 downto 0);
		PC_READY_IN : IN std_logic;          
		CTS_DATA_OUT : OUT std_logic_vector(31 downto 0);
		CTS_DATAREADY_OUT : OUT std_logic;
		CTS_READOUT_FINISHED_OUT : OUT std_logic;
		CTS_LENGTH_OUT : OUT std_logic_vector(15 downto 0);
		CTS_ERROR_PATTERN_OUT : OUT std_logic_vector(31 downto 0);
		FEE_READ_OUT : OUT std_logic;
		PC_WR_EN_OUT : OUT std_logic;
		PC_DATA_OUT : OUT std_logic_vector(7 downto 0);
		PC_SOS_OUT : OUT std_logic;
		PC_EOD_OUT : OUT std_logic;
		PC_SUB_SIZE_OUT : OUT std_logic_vector(31 downto 0);
		PC_TRIG_NR_OUT : OUT std_logic_vector(31 downto 0);
		PC_PADDING_OUT : OUT std_logic;
		BSM_SAVE_OUT : OUT std_logic_vector(3 downto 0);
		BSM_LOAD_OUT : OUT std_logic_vector(3 downto 0);
		DBG_REM_CTR_OUT : OUT std_logic_vector(3 downto 0);
		DBG_CTS_CTR_OUT : OUT std_logic_vector(2 downto 0);
		DBG_SF_WCNT_OUT : OUT std_logic_vector(15 downto 0);
		DBG_SF_RCNT_OUT : OUT std_logic_vector(16 downto 0);
		DBG_SF_DATA_OUT : OUT std_logic_vector(15 downto 0);
		DBG_SF_RD_EN_OUT : OUT std_logic;
		DBG_SF_WR_EN_OUT : OUT std_logic;
		DBG_SF_EMPTY_OUT : OUT std_logic;
		DBG_SF_AEMPTY_OUT : OUT std_logic;
		DBG_SF_FULL_OUT : OUT std_logic;
		DBG_SF_AFULL_OUT : OUT std_logic;
		DEBUG_OUT : OUT std_logic_vector(31 downto 0)
		);
	END COMPONENT;

	SIGNAL CLK :  std_logic;
	SIGNAL RESET :  std_logic;
	SIGNAL START_CONFIG_OUT :  std_logic;
	SIGNAL BANK_SELECT_OUT :  std_logic_vector(3 downto 0);
	SIGNAL CONFIG_DONE_IN :  std_logic;
	SIGNAL DATA_GBE_ENABLE_IN :  std_logic;
	SIGNAL DATA_IPU_ENABLE_IN :  std_logic;
	SIGNAL MULTI_EVT_ENABLE_IN :  std_logic;
	SIGNAL CTS_NUMBER_IN :  std_logic_vector(15 downto 0);
	SIGNAL CTS_CODE_IN :  std_logic_vector(7 downto 0);
	SIGNAL CTS_INFORMATION_IN :  std_logic_vector(7 downto 0);
	SIGNAL CTS_READOUT_TYPE_IN :  std_logic_vector(3 downto 0);
	SIGNAL CTS_START_READOUT_IN :  std_logic;
	SIGNAL CTS_READ_IN :  std_logic;
	SIGNAL CTS_DATA_OUT :  std_logic_vector(31 downto 0);
	SIGNAL CTS_DATAREADY_OUT :  std_logic;
	SIGNAL CTS_READOUT_FINISHED_OUT :  std_logic;
	SIGNAL CTS_LENGTH_OUT :  std_logic_vector(15 downto 0);
	SIGNAL CTS_ERROR_PATTERN_OUT :  std_logic_vector(31 downto 0);
	SIGNAL FEE_DATA_IN :  std_logic_vector(15 downto 0);
	SIGNAL FEE_DATAREADY_IN :  std_logic;
	SIGNAL FEE_READ_OUT :  std_logic;
	SIGNAL FEE_BUSY_IN :  std_logic;
	SIGNAL FEE_STATUS_BITS_IN :  std_logic_vector(31 downto 0);
	SIGNAL PC_WR_EN_OUT :  std_logic;
	SIGNAL PC_DATA_OUT :  std_logic_vector(7 downto 0);
	SIGNAL PC_READY_IN :  std_logic;
	SIGNAL PC_SOS_OUT :  std_logic;
	SIGNAL PC_EOD_OUT :  std_logic;
	SIGNAL PC_SUB_SIZE_OUT :  std_logic_vector(31 downto 0);
	SIGNAL PC_TRIG_NR_OUT :  std_logic_vector(31 downto 0);
	SIGNAL PC_PADDING_OUT :  std_logic;
	SIGNAL BSM_SAVE_OUT :  std_logic_vector(3 downto 0);
	SIGNAL BSM_LOAD_OUT :  std_logic_vector(3 downto 0);
	SIGNAL DBG_REM_CTR_OUT :  std_logic_vector(3 downto 0);
	SIGNAL DBG_CTS_CTR_OUT :  std_logic_vector(2 downto 0);
	SIGNAL DBG_SF_WCNT_OUT :  std_logic_vector(15 downto 0);
	SIGNAL DBG_SF_RCNT_OUT :  std_logic_vector(16 downto 0);
	SIGNAL DBG_SF_DATA_OUT :  std_logic_vector(15 downto 0);
	SIGNAL DBG_SF_RD_EN_OUT :  std_logic;
	SIGNAL DBG_SF_WR_EN_OUT :  std_logic;
	SIGNAL DBG_SF_EMPTY_OUT :  std_logic;
	SIGNAL DBG_SF_AEMPTY_OUT :  std_logic;
	SIGNAL DBG_SF_FULL_OUT :  std_logic;
	SIGNAL DBG_SF_AFULL_OUT :  std_logic;
	SIGNAL DEBUG_OUT :  std_logic_vector(31 downto 0);

BEGIN

-- Please check and add your generic clause manually
	uut: trb_net16_ipu2gbe PORT MAP(
		CLK => CLK,
		RESET => RESET,
		START_CONFIG_OUT => START_CONFIG_OUT,
		BANK_SELECT_OUT => BANK_SELECT_OUT,
		CONFIG_DONE_IN => CONFIG_DONE_IN,
		DATA_GBE_ENABLE_IN => DATA_GBE_ENABLE_IN,
		DATA_IPU_ENABLE_IN => DATA_IPU_ENABLE_IN,
		MULTI_EVT_ENABLE_IN => MULTI_EVT_ENABLE_IN,
		CTS_NUMBER_IN => CTS_NUMBER_IN,
		CTS_CODE_IN => CTS_CODE_IN,
		CTS_INFORMATION_IN => CTS_INFORMATION_IN,
		CTS_READOUT_TYPE_IN => CTS_READOUT_TYPE_IN,
		CTS_START_READOUT_IN => CTS_START_READOUT_IN,
		CTS_READ_IN => CTS_READ_IN,
		CTS_DATA_OUT => CTS_DATA_OUT,
		CTS_DATAREADY_OUT => CTS_DATAREADY_OUT,
		CTS_READOUT_FINISHED_OUT => CTS_READOUT_FINISHED_OUT,
		CTS_LENGTH_OUT => CTS_LENGTH_OUT,
		CTS_ERROR_PATTERN_OUT => CTS_ERROR_PATTERN_OUT,
		FEE_DATA_IN => FEE_DATA_IN,
		FEE_DATAREADY_IN => FEE_DATAREADY_IN,
		FEE_READ_OUT => FEE_READ_OUT,
		FEE_BUSY_IN => FEE_BUSY_IN,
		FEE_STATUS_BITS_IN => FEE_STATUS_BITS_IN,
		PC_WR_EN_OUT => PC_WR_EN_OUT,
		PC_DATA_OUT => PC_DATA_OUT,
		PC_READY_IN => PC_READY_IN,
		PC_SOS_OUT => PC_SOS_OUT,
		PC_EOD_OUT => PC_EOD_OUT,
		PC_SUB_SIZE_OUT => PC_SUB_SIZE_OUT,
		PC_TRIG_NR_OUT => PC_TRIG_NR_OUT,
		PC_PADDING_OUT => PC_PADDING_OUT,
		BSM_SAVE_OUT => BSM_SAVE_OUT,
		BSM_LOAD_OUT => BSM_LOAD_OUT,
		DBG_REM_CTR_OUT => DBG_REM_CTR_OUT,
		DBG_CTS_CTR_OUT => DBG_CTS_CTR_OUT,
		DBG_SF_WCNT_OUT => DBG_SF_WCNT_OUT,
		DBG_SF_RCNT_OUT => DBG_SF_RCNT_OUT,
		DBG_SF_DATA_OUT => DBG_SF_DATA_OUT,
		DBG_SF_RD_EN_OUT => DBG_SF_RD_EN_OUT,
		DBG_SF_WR_EN_OUT => DBG_SF_WR_EN_OUT,
		DBG_SF_EMPTY_OUT => DBG_SF_EMPTY_OUT,
		DBG_SF_AEMPTY_OUT => DBG_SF_AEMPTY_OUT,
		DBG_SF_FULL_OUT => DBG_SF_FULL_OUT,
		DBG_SF_AFULL_OUT => DBG_SF_AFULL_OUT,
		DEBUG_OUT => DEBUG_OUT
	);

CLOCK_GEN: process
begin
	clk <= '1'; wait for 5.0 ns;
	clk <= '0'; wait for 5.0 ns;
end process CLOCK_GEN;

PC_READY_PROC: process
begin
	pc_ready_in <= '0';
	wait for 500 ns;
	pc_ready_in <= '1';
	wait for 500 ns;
	pc_ready_in <= '0';
	wait for 99 us;
end process PC_READY_PROC;

-- Testbench
TESTBENCH_PROC: process
-- test data from TRBnet
variable test_data_len : integer range 0 to 65535 := 1;
variable test_loop_len : integer range 0 to 65535 := 0;
variable test_hdr_len : unsigned(15 downto 0) := x"0000";
variable test_evt_len : unsigned(15 downto 0) := x"0000";
variable test_data : unsigned(15 downto 0) := x"ffff";

variable trigger_counter : unsigned(15 downto 0) := x"4710";
variable trigger_loop : integer range 0 to 65535 := 15;

-- 1400 bytes MTU => 350 as limit for fragmentation
variable max_event_size : real := 512.0;
--variable max_event_size : real := 1024.0;

variable seed1 : positive; -- seed for random generator
variable seed2 : positive; -- seed for random generator
variable rand : real; -- random value (0.0 ... 1.0)
variable int_rand : integer; -- random value, scaled to your needs
variable cts_random_number : std_logic_vector(7 downto 0);

variable stim : std_logic_vector(15 downto 0);

begin
	-- Setup signals
	reset <= '0';
	cts_number_in <= x"0000";
	cts_code_in <= x"00";
	cts_information_in <= x"00";
	cts_readout_type_in <= x"0";
	cts_start_readout_in <= '0';
	cts_read_in <= '0';
	fee_data_in <= x"0000";
	fee_dataready_in <= '0';
	fee_status_bits_in <= x"0000_0000";
	fee_busy_in <= '0';
--	pc_ready_in <= '0';

	config_done_in <= '1';
	data_gbe_enable_in <= '1';
	data_ipu_enable_in <= '0';
	multi_evt_enable_in <= '0';

	wait for 22 ns;
	
	-- Reset the whole stuff
	wait until rising_edge(clk);
	reset <= '1';
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	reset <= '0';
	wait until rising_edge(clk);
	wait for 200 ns;

---------------------------

-------------------------------------------------------------------------------
-- Loop the transmissions
-------------------------------------------------------------------------------
	trigger_counter := x"4710";
	trigger_loop    := 40;

	MY_TRIGGER_LOOP: for J in 0 to trigger_loop loop
		-- generate a real random byte for CTS
		UNIFORM(seed1, seed2, rand);
		int_rand := INTEGER(TRUNC(rand*256.0));
		cts_random_number := std_logic_vector(to_unsigned(int_rand, cts_random_number'LENGTH));
	
		-- IPU transmission starts
		wait until rising_edge(clk);
		cts_number_in <= std_logic_vector( trigger_counter );
		cts_code_in <= cts_random_number;
		cts_information_in <= x"de";
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
		test_data_len := INTEGER(TRUNC(rand*max_event_size)) + 1;
		
--		test_data_len := 9685;
		
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
			wait until rising_edge(clk) and (fee_read_out = '1'); --
			fee_data_in <= std_logic_vector(test_data); 
			if( (test_data MOD 5) = 0 ) then
				fee_dataready_in <= '0';
--				wait until rising_edge(clk);
--				wait until rising_edge(clk);
--				wait until rising_edge(clk);
--				wait until rising_edge(clk);
--				wait until rising_edge(clk);
--				wait until rising_edge(clk);
--				wait until rising_edge(clk);
--				wait until rising_edge(clk);
--				wait until rising_edge(clk);
--				wait until rising_edge(clk);
--				wait until rising_edge(clk);
--				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				wait until rising_edge(clk);
				fee_dataready_in <= '1';
			else
				fee_dataready_in <= '1';
			end if;
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



---------------------------
---------------------------
	wait for 300 ns;

	wait;

	-- Start packet_constructor
	wait until rising_edge(clk);
	wait until rising_edge(clk);
--	pc_ready_in <= '1';
	wait until rising_edge(clk);

	wait until rising_edge(clk);
	wait until pc_eod_out = '1';
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	wait until rising_edge(clk);
--	pc_ready_in <= '0';

	-- Stay a while... stay forever!!!
	wait;	
	
end process TESTBENCH_PROC;


END;
