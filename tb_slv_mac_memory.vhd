LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY testbench IS
END testbench;

ARCHITECTURE behavior OF testbench IS 

	COMPONENT slv_mac_memory
	PORT(
		CLK : IN std_logic;
		RESET : IN std_logic;
		BUSY_IN : IN std_logic;
		SLV_ADDR_IN : IN std_logic_vector(7 downto 0);
		SLV_READ_IN : IN std_logic;
		SLV_WRITE_IN : IN std_logic;
		SLV_DATA_IN : IN std_logic_vector(31 downto 0);
		MEM_CLK_IN : IN std_logic;
		MEM_ADDR_IN : IN std_logic_vector(7 downto 0);          
		SLV_BUSY_OUT : OUT std_logic;
		SLV_ACK_OUT : OUT std_logic;
		SLV_DATA_OUT : OUT std_logic_vector(31 downto 0);
		MEM_DATA_OUT : OUT std_logic_vector(31 downto 0);
		STAT : OUT std_logic_vector(31 downto 0)
		);
	END COMPONENT;

	SIGNAL CLK :  std_logic;
	SIGNAL RESET :  std_logic;
	SIGNAL BUSY_IN :  std_logic;
	SIGNAL SLV_ADDR_IN :  std_logic_vector(7 downto 0);
	SIGNAL SLV_READ_IN :  std_logic;
	SIGNAL SLV_WRITE_IN :  std_logic;
	SIGNAL SLV_BUSY_OUT :  std_logic;
	SIGNAL SLV_ACK_OUT :  std_logic;
	SIGNAL SLV_DATA_IN :  std_logic_vector(31 downto 0);
	SIGNAL SLV_DATA_OUT :  std_logic_vector(31 downto 0);
	SIGNAL MEM_CLK_IN :  std_logic;
	SIGNAL MEM_ADDR_IN :  std_logic_vector(7 downto 0);
	SIGNAL MEM_DATA_OUT :  std_logic_vector(31 downto 0);
	SIGNAL STAT :  std_logic_vector(31 downto 0);

BEGIN

-- Please check and add your generic clause manually
	uut: slv_mac_memory PORT MAP(
		CLK => CLK,
		RESET => RESET,
		BUSY_IN => BUSY_IN,
		SLV_ADDR_IN => SLV_ADDR_IN,
		SLV_READ_IN => SLV_READ_IN,
		SLV_WRITE_IN => SLV_WRITE_IN,
		SLV_BUSY_OUT => SLV_BUSY_OUT,
		SLV_ACK_OUT => SLV_ACK_OUT,
		SLV_DATA_IN => SLV_DATA_IN,
		SLV_DATA_OUT => SLV_DATA_OUT,
		MEM_CLK_IN => MEM_CLK_IN,
		MEM_ADDR_IN => MEM_ADDR_IN,
		MEM_DATA_OUT => MEM_DATA_OUT,
		STAT => STAT
	);

CLK_GEN_PROC: process
begin
	clk <= '0'; mem_clk_in <= '0'; wait for 5.0 ns;
	clk <= '1'; mem_clk_in <= '1'; wait for 5.0 ns;
end process CLK_GEN_PROC;

THE_TESTBENCH: process
begin
	-- Setup signals
	reset <= '0';
	busy_in <= '0';
	slv_addr_in <= x"00";
	slv_read_in <= '0';
	slv_write_in <= '0';
	slv_data_in <= x"dead_beef";
	mem_addr_in <= x"f0";
	wait until rising_edge(clk);
	
	-- Reset the whole stuff
	wait until rising_edge(clk);
	reset <= '1';
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	reset <= '0';
	wait until rising_edge(clk);
	
	-- Tests may start now
	wait until rising_edge(clk);
	mem_addr_in <= x"00";
	wait until rising_edge(clk);
	mem_addr_in <= x"01";
	wait until rising_edge(clk);
	mem_addr_in <= x"02";
	wait until rising_edge(clk);
	mem_addr_in <= x"03";
	wait until rising_edge(clk);
	mem_addr_in <= x"04";
	wait until rising_edge(clk);
	mem_addr_in <= x"05";
	wait until rising_edge(clk);
	mem_addr_in <= x"06";
	wait until rising_edge(clk);
	mem_addr_in <= x"07";
	wait until rising_edge(clk);
	mem_addr_in <= x"08";
	
	-- Stay a while... stay forever!!! Muahahaha!!!!!
	wait;
end process THE_TESTBENCH;

END;
