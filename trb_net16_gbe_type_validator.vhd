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
-- contains valid frame types codes and performs checking 
-- by default there is place for 32 frame type which is hardcoded value
-- due to allow register which is set by slow control

entity trb_net16_gbe_type_validator is
port (
	FRAME_TYPE_IN		: in	std_logic_vector(15 downto 0);  -- recovered frame type	
	ALLOWED_TYPES_IN	: in	std_logic_vector(31 downto 0);  -- signal from gbe_setup
	
	VALID_OUT		: out	std_logic
);
end trb_net16_gbe_type_validator;


architecture trb_net16_gbe_type_validator of trb_net16_gbe_type_validator is

type frame_types_a is array(31 downto 0) of std_logic_vector(15 downto 0);
signal FRAME_TYPES : frame_types_a;

signal result                   : std_logic_vector(31 downto 0);

begin

--**** HERE ADD YOUR FRAME TYPE CODE ****
-- frame type constants declaration
FRAME_TYPES(0)  <= x"0800";  -- IPv4
FRAME_TYPES(1)  <= x"0806";  -- ARP

SET_GEN : for i in 2 to 31 generate
	FRAME_TYPES(i)  <= (others => '0');
end generate SET_GEN;
-- end


-- DO NOT TOUCH
RESULT_GEN : for i in 0 to 31 generate

	result(i) <= '1' when (
				FRAME_TYPES(i)(31 downto 16) = FRAME_TYPE_IN(15 downto 0) and 
				FRAME_TYPES(i)(15 downto 0) = FRAME_TYPE_IN(31 downto 16) and
				ALLOWED_TYPES_IN(i) = '1'
			) else '0';

end generate RESULT_GEN;

VALID_OUT <= or_all(result);


end trb_net16_gbe_type_validator;


