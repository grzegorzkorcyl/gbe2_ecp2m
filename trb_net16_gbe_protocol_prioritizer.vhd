LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;
use work.trb_net16_hub_func.all;

use work.trb_net_gbe_components.all;
use work.trb_net_gbe_protocols.all;

--********
-- maps the frame type and protocol code into internal value which sets the priority

entity trb_net16_gbe_protocol_prioritizer is
port (
	FRAME_TYPE_IN		: in	std_logic_vector(15 downto 0);  -- recovered frame type	
	PROTOCOL_CODE_IN	: in	std_logic_vector(15 downto 0);  -- higher level protocols
	HAS_HIGHER_LEVEL_IN	: in	std_logic;
	
	CODE_OUT		: out	std_logic_vector(c_MAX_PROTOCOLS - 1 downto 0)
);
end trb_net16_gbe_protocol_prioritizer;


architecture trb_net16_gbe_protocol_prioritizer of trb_net16_gbe_protocol_prioritizer is

begin

PRIORITIZE : process(FRAME_TYPE_IN, PROTOCOL_CODE_IN, HAS_HIGHER_LEVEL_IN)
begin

	CODE_OUT <= (others => '0');

	--**** HERE ADD YOU PROTOCOL RECOGNITION AT WANTED PRIORITY LEVEL
	case FRAME_TYPE_IN is
	
		-- No. 1 = IPv4 
		when x"0800" =>
			if (HAS_HIGHER_LEVEL_IN = '1') then
				-- in case there is another protocol inside IPv4 frame
				CODE_OUT(0) <= '1';
			else
				-- branch for pure IPv4
				CODE_OUT(0) <= '1';
			end if;
		
		-- No. 2 = ARP
		when x"0806" =>
			CODE_OUT(1) <= '1'; 
		
		-- No. 3 = Test
		when x"08AA" =>
			CODE_OUT(2) <= '1';
		
		-- CODE_OUT full of 1 is invalid value for the rest of the logic
		when others =>
			CODE_OUT <= (others => '1');
	
	end case;

end process PRIORITIZE;

end trb_net16_gbe_protocol_prioritizer;


