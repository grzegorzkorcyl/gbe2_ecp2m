library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;
--use work.adcmv3_components.all;


entity slv_register is
generic( RESET_VALUE	: std_logic_vector(31 downto 0) := x"0000_0000" );
port( CLK_IN		: in	std_logic;
	  RESET_IN		: in	std_logic;
	  BUSY_IN		: in	std_logic;
	  -- Slave bus
	  SLV_READ_IN	: in	std_logic;
	  SLV_WRITE_IN	: in 	std_logic;
	  SLV_BUSY_OUT	: out	std_logic;
	  SLV_ACK_OUT	: out	std_logic;
	  SLV_DATA_IN	: in	std_logic_vector(31 downto 0);
	  SLV_DATA_OUT	: out	std_logic_vector(31 downto 0);
	  -- I/O to the backend
	  REG_DATA_IN	: in	std_logic_vector(31 downto 0);
	  REG_DATA_OUT	: out	std_logic_vector(31 downto 0);
	  -- Status lines
	  STAT			: out	std_logic_vector(31 downto 0) -- DEBUG
	);
end entity;

architecture Behavioral of slv_register is

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

	signal reg_slv_data_in	: std_logic_vector(31 downto 0); -- registered data input
	signal reg_slv_data_out	: std_logic_vector(31 downto 0); -- read back data
	signal reg_busy			: std_logic;

begin

-- Fake
reg_busy <= busy_in;
stat <= (others => '0');

---------------------------------------------------------
-- Statemachine                                        --
---------------------------------------------------------
-- State memory process
STATE_MEM: process( clk_in )
begin
	if( rising_edge(clk_in) ) then
		if( reset_in = '1' ) then
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
								slv_busy_x <= '1'; -- added 23022009
							elsif( (reg_busy = '1') and (slv_write_in = '1') ) then
								NEXT_STATE <= WR_BSY;
								slv_busy_x <= '1'; -- added 23022009
							else	
								NEXT_STATE <= SLEEP;
							end if;
		when RD_RDY		=>	NEXT_STATE <= RD_ACK;
							slv_ack_x  <= '1';
		when WR_RDY		=>	NEXT_STATE <= WR_ACK;
							slv_ack_x  <= '1';
		when RD_ACK		=>	if( slv_read_in = '0' ) then
								NEXT_STATE <= DONE;
							else
								NEXT_STATE <= RD_ACK;
								slv_ack_x  <= '1';
							end if;
		when WR_ACK		=>	if( slv_write_in = '0' ) then
								NEXT_STATE <= DONE;
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

-- register write
THE_WRITE_REG_PROC: process( clk_in )
begin
	if( rising_edge(clk_in) ) then
		if   ( reset_in = '1' ) then
			reg_slv_data_in <= RESET_VALUE;
		elsif( store_wr = '1' ) then
			reg_slv_data_in <= slv_data_in;
		end if;
	end if;
end process THE_WRITE_REG_PROC;

-- register read
THE_READ_REG_PROC: process( clk_in )
begin
	if( rising_edge(clk_in) ) then
		if   ( reset_in = '1' ) then
			reg_slv_data_out <= (others => '0');
		elsif( store_rd = '1' ) then
			reg_slv_data_out <= reg_data_in;
		end if;
	end if;
end process THE_READ_REG_PROC;

-- output signals
slv_ack_out  <= slv_ack;
slv_busy_out <= slv_busy;
slv_data_out <= reg_slv_data_out;

---------------------------------------------------------
-- signals to backend                                  --
---------------------------------------------------------

reg_data_out <= reg_slv_data_in;

end Behavioral;
