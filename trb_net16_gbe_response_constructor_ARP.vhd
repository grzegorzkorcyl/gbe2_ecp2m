LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;
use work.trb_net16_hub_func.all;

--********
-- dissects the incoming packet of the specified protocol
-- and constructs the responses if needed

entity trb_net16_gbe_response_constructor_ARP is
port (
	CLK			: in	std_logic;  -- system clock
	RESET			: in	std_logic;

	-- signals from ip_configurator used by packet constructor
	IC_DEST_MAC_ADDRESS_IN     : in    std_logic_vector(47 downto 0);
	IC_DEST_IP_ADDRESS_IN      : in    std_logic_vector(31 downto 0);
	IC_DEST_UDP_PORT_IN        : in    std_logic_vector(15 downto 0);
	IC_SRC_MAC_ADDRESS_IN      : in    std_logic_vector(47 downto 0);
	IC_SRC_IP_ADDRESS_IN       : in    std_logic_vector(31 downto 0);
	IC_SRC_UDP_PORT_IN         : in    std_logic_vector(15 downto 0);

	-- signal to/from main controller
	MC_TREAT_PACKET_IN	  : in	std_logic;  -- pulse when the frame is received and recognized to be treated by this entity
	MC_DATA_IN		  : in	std_logic_vector(8 downto 0);
	MC_RD_EN_OUT		  : out	std_logic;
	MC_TX_BUSY_IN		  : in	std_logic;  -- asserted when response cannot be sent 

	-- signal to/from frame constructor
	FC_DATA_OUT		: out	std_logic_vector(7 downto 0);
	FC_WR_EN_OUT		: out	std_logic;
	FC_READY_IN		: in	std_logic;
	FC_H_READY_IN		: in	std_logic;
	FC_IP_SIZE_OUT		: out	std_logic_vector(15 downto 0);
	FC_UDP_SIZE_OUT		: out	std_logic_vector(15 downto 0);
	FC_IDENT_OUT		: out	std_logic_vector(15 downto 0);  -- internal packet counter
	FC_FLAGS_OFFSET_OUT	: out	std_logic_vector(15 downto 0);
	FC_SOD_OUT		: out	std_logic;
	FC_EOD_OUT		: out	std_logic;

	DEST_MAC_ADDRESS_OUT    : out    std_logic_vector(47 downto 0);
	DEST_IP_ADDRESS_OUT     : out    std_logic_vector(31 downto 0);
	DEST_UDP_PORT_OUT       : out    std_logic_vector(15 downto 0);
	SRC_MAC_ADDRESS_OUT     : out    std_logic_vector(47 downto 0);
	SRC_IP_ADDRESS_OUT      : out    std_logic_vector(31 downto 0);
	SRC_UDP_PORT_OUT        : out    std_logic_vector(15 downto 0);


-- debug
	DEBUG_OUT		: out	std_logic_vector(63 downto 0)
);
end trb_net16_gbe_response_constructor_ARP;


architecture trb_net16_gbe_response_constructor_ARP of trb_net16_gbe_response_constructor_ARP is

attribute syn_encoding	: string;

type dissect_states is (IDLE, READ_SOMETHING, CLEANUP);
signal dissect_current_state, dissect_next_state : dissect_states;
attribute syn_encoding of dissect_current_state: signal is "safe,gray";

begin




end trb_net16_gbe_response_constructor_ARP;


