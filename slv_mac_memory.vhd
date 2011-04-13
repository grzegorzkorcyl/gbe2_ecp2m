library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;

entity slv_mac_memory is
port( 
	CLK				: in	std_logic;
	RESET			: in	std_logic;
	BUSY_IN			: in	std_logic;
	-- Slave bus
	SLV_ADDR_IN		: in    std_logic_vector(7 downto 0);
	SLV_READ_IN		: in	std_logic;
	SLV_WRITE_IN	: in 	std_logic;
	SLV_BUSY_OUT	: out	std_logic;
	SLV_ACK_OUT		: out	std_logic;
	SLV_DATA_IN		: in	std_logic_vector(31 downto 0);
	SLV_DATA_OUT	: out	std_logic_vector(31 downto 0);
	-- I/O to the backend
	MEM_CLK_IN		: in	std_logic;
	MEM_ADDR_IN		: in	std_logic_vector(7 downto 0);
	MEM_DATA_OUT	: out	std_logic_vector(31 downto 0);
	-- Status lines
	STAT			: out	std_logic_vector(31 downto 0) -- DEBUG
);
end entity;

architecture Behavioral of slv_mac_memory is

component ip_mem is
port( 
	DataInA		: in	std_logic_vector(31 downto 0); 
	DataInB		: in	std_logic_vector(31 downto 0); 
	AddressA	: in	std_logic_vector(7 downto 0); 
	AddressB	: in	std_logic_vector(7 downto 0); 
	ClockA		: in	std_logic; 
	ClockB		: in	std_logic; 
	ClockEnA	: in	std_logic; 
	ClockEnB	: in	std_logic; 
	WrA			: in	std_logic; 
	WrB			: in	std_logic; 
	ResetA		: in	std_logic; 
	ResetB		: in	std_logic; 
	QA			: out	std_logic_vector(31 downto 0); 
	QB			: out	std_logic_vector(31 downto 0)
);
end component ip_mem;

-- Signals
type STATES is (SLEEP,RD_BSY,WR_BSY,RD_RDY,WR_RDY,RD_ACK,WR_ACK,DONE);
signal CURRENT_STATE, NEXT_STATE: STATES;

-- slave bus signals
signal slv_busy_x		: std_logic;
signal slv_busy			: std_logic;
signal slv_ack_x		: std_logic;
signal slv_ack			: std_logic;
signal store_wr_x		: std_logic;
signal store_wr			: std_logic;
signal store_rd_x		: std_logic;
signal store_rd			: std_logic;

signal reg_busy			: std_logic;

begin

-- Fake
reg_busy <= busy_in;
stat <= (others => '0');

---------------------------------------------------------
-- Statemachine                                        --
---------------------------------------------------------
-- State memory process
STATE_MEM: process( clk )
begin
	if( rising_edge(clk) ) then
		if( reset = '1' ) then
			CURRENT_STATE <= SLEEP;
			slv_busy      <= '0';
			slv_ack       <= '0';
			store_wr      <= '0';
			store_rd      <= '0';
		else
			CURRENT_STATE <= NEXT_STATE;
			slv_busy      <= slv_busy_x;
			slv_ack       <= slv_ack_x;
			store_wr      <= store_wr_x;
			store_rd      <= store_rd_x;
		end if;
	end if;
end process STATE_MEM;

-- Transition matrix
TRANSFORM: process(CURRENT_STATE, slv_read_in, slv_write_in, reg_busy )
begin
	NEXT_STATE <= SLEEP;
	slv_busy_x <= '0';
	slv_ack_x  <= '0';
	store_wr_x <= '0';
	store_rd_x <= '0';
	case CURRENT_STATE is
		when SLEEP		=>	if   ( (reg_busy = '0') and (slv_read_in = '1') ) then
								NEXT_STATE <= RD_RDY;
								store_rd_x <= '1';
							elsif( (reg_busy = '0') and (slv_write_in = '1') ) then
								NEXT_STATE <= WR_RDY;
								store_wr_x <= '1';
							elsif( (reg_busy = '1') and (slv_read_in = '1') ) then
								NEXT_STATE <= RD_BSY;
							elsif( (reg_busy = '1') and (slv_write_in = '1') ) then
								NEXT_STATE <= WR_BSY;
							else	
								NEXT_STATE <= SLEEP;
							end if;
		when RD_RDY		=>	NEXT_STATE <= RD_ACK;
		when WR_RDY		=>	NEXT_STATE <= WR_ACK;
		when RD_ACK		=>	if( slv_read_in = '0' ) then
								NEXT_STATE <= DONE;
								slv_ack_x  <= '1';
							else
								NEXT_STATE <= RD_ACK;
								slv_ack_x  <= '1';
							end if;
		when WR_ACK		=>	if( slv_write_in = '0' ) then
								NEXT_STATE <= DONE;
								slv_ack_x  <= '1';
							else
								NEXT_STATE <= WR_ACK;
								slv_ack_x  <= '1';
							end if;
		when RD_BSY		=>	if( slv_read_in = '0' ) then
								NEXT_STATE <= DONE;
							else
								NEXT_STATE <= RD_BSY;
								slv_busy_x <= '1';
							end if;
		when WR_BSY		=>	if( slv_write_in = '0' ) then
								NEXT_STATE <= DONE;
							else
								NEXT_STATE <= WR_BSY;
								slv_busy_x <= '1';
							end if;
		when DONE		=>	NEXT_STATE <= SLEEP;
			
		when others		=>	NEXT_STATE <= SLEEP;
	end case;
end process TRANSFORM;

---------------------------------------------------------
-- data handling                                       --
---------------------------------------------------------

THE_MAC_MEM: ip_mem
port map( 
	DataInA		=> slv_data_in,
	AddressA	=> slv_addr_in,
	ClockA		=> clk,
	ClockEnA	=> '1',
	QA			=> slv_data_out,
	WrA			=> store_wr, 
	ResetA		=> reset, 
	DataInB		=> x"0000_0000",  
	AddressB	=> mem_addr_in, 
	ClockB		=> mem_clk_in, 
	ClockEnB	=> '1', 
	WrB			=> '0', -- never write
	ResetB		=> reset,
	QB			=> mem_data_out
);

-- output signals
slv_ack_out  <= slv_ack;
slv_busy_out <= slv_busy;

end Behavioral;
