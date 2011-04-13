LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY testbench IS
END testbench;

ARCHITECTURE behavior OF testbench IS 

	COMPONENT ip_configurator
	PORT(
		CLK : IN std_logic;
		RESET : IN std_logic;
		START_CONFIG_IN : IN std_logic;
		BANK_SELECT_IN : IN std_logic_vector(3 downto 0);
		MEM_DATA_IN : IN std_logic_vector(31 downto 0);          
		CONFIG_DONE_OUT : OUT std_logic;
		MEM_ADDR_OUT : OUT std_logic_vector(7 downto 0);
		MEM_CLK_OUT : OUT std_logic;
		DEST_MAC_OUT : OUT std_logic_vector(47 downto 0);
		DEST_IP_OUT : OUT std_logic_vector(31 downto 0);
		DEST_UDP_OUT : OUT std_logic_vector(15 downto 0);
		SRC_MAC_OUT : OUT std_logic_vector(47 downto 0);
		SRC_IP_OUT : OUT std_logic_vector(31 downto 0);
		SRC_UDP_OUT : OUT std_logic_vector(15 downto 0);
		MTU_OUT : OUT std_logic_vector(15 downto 0);
		DEBUG_OUT : OUT std_logic_vector(31 downto 0)
		);
	END COMPONENT;

	SIGNAL CLK :  std_logic;
	SIGNAL RESET :  std_logic;
	SIGNAL START_CONFIG_IN :  std_logic;
	SIGNAL BANK_SELECT_IN :  std_logic_vector(3 downto 0);
	SIGNAL CONFIG_DONE_OUT :  std_logic;
	SIGNAL MEM_ADDR_OUT :  std_logic_vector(7 downto 0);
	SIGNAL MEM_DATA_IN :  std_logic_vector(31 downto 0);
	SIGNAL MEM_CLK_OUT :  std_logic;
	SIGNAL DEST_MAC_OUT :  std_logic_vector(47 downto 0);
	SIGNAL DEST_IP_OUT :  std_logic_vector(31 downto 0);
	SIGNAL DEST_UDP_OUT :  std_logic_vector(15 downto 0);
	SIGNAL SRC_MAC_OUT :  std_logic_vector(47 downto 0);
	SIGNAL SRC_IP_OUT :  std_logic_vector(31 downto 0);
	SIGNAL SRC_UDP_OUT :  std_logic_vector(15 downto 0);
	SIGNAL MTU_OUT :  std_logic_vector(15 downto 0);
	SIGNAL DEBUG_OUT :  std_logic_vector(31 downto 0);

BEGIN

-- Please check and add your generic clause manually
	uut: ip_configurator PORT MAP(
		CLK => CLK,
		RESET => RESET,
		START_CONFIG_IN => START_CONFIG_IN,
		BANK_SELECT_IN => BANK_SELECT_IN,
		CONFIG_DONE_OUT => CONFIG_DONE_OUT,
		MEM_ADDR_OUT => MEM_ADDR_OUT,
		MEM_DATA_IN => MEM_DATA_IN,
		MEM_CLK_OUT => MEM_CLK_OUT,
		DEST_MAC_OUT => DEST_MAC_OUT,
		DEST_IP_OUT => DEST_IP_OUT,
		DEST_UDP_OUT => DEST_UDP_OUT,
		SRC_MAC_OUT => SRC_MAC_OUT,
		SRC_IP_OUT => SRC_IP_OUT,
		SRC_UDP_OUT => SRC_UDP_OUT,
		MTU_OUT => MTU_OUT,
		DEBUG_OUT => DEBUG_OUT
	);


CLK_GEN_PROC: process
begin
	clk <= '0'; wait for 5.0 ns;
	clk <= '1'; wait for 5.0 ns;
end process CLK_GEN_PROC;

THE_TESTBENCH: process
begin
	-- Setup signals
	reset <= '0';
	start_config_in <= '0';
	bank_select_in <= x"0";
	mem_data_in <= x"0000_0000";
	
	-- Reset the whole stuff
	wait until rising_edge(clk);
	reset <= '1';
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	reset <= '0';
	wait for 100 ns;
	wait until rising_edge(clk);
	
	-- Tests may start now
	wait until rising_edge(clk);
	start_config_in <= '1';
	wait until mem_addr_out(3 downto 0) = x"1";
	wait until rising_edge(clk);
	mem_data_in <= x"4902d745"; -- dest MAC low
	wait until rising_edge(clk);
	mem_data_in <= x"00006cf0"; -- dest MAC high
	wait until rising_edge(clk);
	mem_data_in <= x"c0a80002"; -- dest IP
	wait until rising_edge(clk);
	mem_data_in <= x"0000c350"; -- dest port
	wait until rising_edge(clk);
	mem_data_in <= x"eeeeeeee"; -- src MAC low
	wait until rising_edge(clk);
	mem_data_in <= x"0000eeee"; -- src MAC high
	wait until rising_edge(clk);
	mem_data_in <= x"c0a80005"; -- src IP
	wait until rising_edge(clk);
	mem_data_in <= x"0000c350"; -- src port
	wait until rising_edge(clk);
	mem_data_in <= x"00000578"; -- MTU
	wait until rising_edge(clk);
	mem_data_in <= x"99999999";
	wait until rising_edge(clk);
	mem_data_in <= x"aaaaaaaa";
	wait until rising_edge(clk);
	mem_data_in <= x"bbbbbbbb";
	wait until rising_edge(clk);
	mem_data_in <= x"cccccccc";
	wait until rising_edge(clk);
	mem_data_in <= x"dddddddd";
	wait until rising_edge(clk);
	mem_data_in <= x"eeeeeeee";
	wait until rising_edge(clk);
	mem_data_in <= x"ffffffff";
	wait until rising_edge(clk);
	mem_data_in <= x"00000000";
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	start_config_in <= '0';
	
	-- Stay a while... stay forever!!! Muahahaha!!!!!
	wait;
end process THE_TESTBENCH;


END;
