LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;
use work.trb_net16_hub_func.all;

use work.trb_net_gbe_components.all;

--********
-- Response Constructor which forwards received frame back ceating a loopback 
--

entity trb_net16_gbe_response_constructor_Forward is
port (
	CLK			: in	std_logic;  -- system clock
	RESET			: in	std_logic;
	
-- INTERFACE	
	PS_DATA_IN		: in	std_logic_vector(8 downto 0);
	PS_WR_EN_IN		: in	std_logic;
	PS_ACTIVATE_IN		: in	std_logic;
	PS_RESPONSE_READY_OUT	: out	std_logic;
	PS_BUSY_OUT		: out	std_logic;
	
	TC_RD_EN_IN		: in	std_logic;
	TC_DATA_OUT		: out	std_logic_vector(8 downto 0);
	TC_FRAME_SIZE_OUT	: out	std_logic_vector(15 downto 0);
-- END OF INTERFACE

-- debug
	DEBUG_OUT		: out	std_logic_vector(63 downto 0)
);
end trb_net16_gbe_response_constructor_Forward;


architecture trb_net16_gbe_response_constructor_Forward of trb_net16_gbe_response_constructor_Forward is

attribute syn_encoding	: string;

type dissect_states is (IDLE, SAVE, LOAD, CLEANUP);
signal dissect_current_state, dissect_next_state : dissect_states;
attribute syn_encoding of dissect_current_state: signal is "safe,gray";

signal ff_wr_en                 : std_logic;
signal resp_bytes_ctr           : std_logic_vector(15 downto 0);
signal ff_empty                 : std_logic;
signal reset_ctr                : std_logic;
signal ff_q                     : std_logic_vector(8 downto 0);
signal ff_wr_lock               : std_logic;
signal ff_wr_lock_q             : std_logic;

begin

DISSECT_MACHINE_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			dissect_current_state <= IDLE;
		else
			dissect_current_state <= dissect_next_state;
		end if;
	end if;
end process DISSECT_MACHINE_PROC;

DISSECT_MACHINE : process(dissect_current_state, PS_WR_EN_IN, PS_ACTIVATE_IN, PS_DATA_IN, ff_q)
begin
	case dissect_current_state is
	
		when IDLE =>
			if (PS_WR_EN_IN = '1' and PS_ACTIVATE_IN = '1') then
				dissect_next_state <= SAVE;
			else
				dissect_next_state <= IDLE;
			end if;
		
		when SAVE =>
			if (PS_DATA_IN(8) = '1') then
				dissect_next_state <= LOAD;
			else
				dissect_next_state <= SAVE;
			end if;
		
		when LOAD =>
			if (ff_q(8) = '1') and (ff_wr_lock_q = '0') then
				dissect_next_state <= CLEANUP;
			else
				dissect_next_state <= LOAD;
			end if;
		
		when CLEANUP =>
			dissect_next_state <= IDLE;
	
	end case;
end process DISSECT_MACHINE;

PS_BUSY_OUT <= '1' when ff_wr_en = '1' else '0';

ff_wr_en <= '1' when (PS_WR_EN_IN = '1' and PS_ACTIVATE_IN = '1') else '0';

FF_WR_LOCK_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		
		ff_wr_lock_q <= ff_wr_lock;
	
		if (RESET = '1') then
			ff_wr_lock <= '0';
		elsif (dissect_current_state = SAVE) then
			ff_wr_lock <= '1';
		else 
			ff_wr_lock <= '0';
		end if;
	end if;
end process FF_WR_LOCK_PROC;

-- TODO: put a smaller fifo here
FRAME_FIFO: fifo_4096x9
port map( 
	Data                => PS_DATA_IN,
	WrClock             => CLK,
	RdClock             => CLK,
	WrEn                => ff_wr_en,
	RdEn                => TC_RD_EN_IN,
	Reset               => RESET,
	RPReset             => RESET,
	Q                   => ff_q,
	Empty               => ff_empty,
	Full                => open
);

TC_DATA_OUT <= ff_q;

PS_RESPONSE_READY_OUT <= '1' when (dissect_current_state = LOAD) else '0';

TC_FRAME_SIZE_OUT <= resp_bytes_ctr + x"1";

RESP_BYTES_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (dissect_current_state = IDLE) then
			resp_bytes_ctr <= (others => '0');
		elsif (dissect_current_state = SAVE) then
			resp_bytes_ctr <= resp_bytes_ctr + x"1";
		end if;
	end if;
end process RESP_BYTES_CTR_PROC;

end trb_net16_gbe_response_constructor_Forward;


