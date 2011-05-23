LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

use work.trb_net_gbe_components.all;
use work.trb_net_gbe_protocols.all;

entity testbench is
end testbench;

architecture behavior of testbench is

signal CLK			: std_logic;
signal RESET			: std_logic;
signal LINK_OK_IN               : std_logic;
signal ALLOW_RX_IN		: std_logic;
signal RX_MAC_CLK		: std_logic;
signal MAC_RX_EOF_IN		: std_logic;
signal MAC_RX_ER_IN		: std_logic;
signal MAC_RXD_IN		: std_logic_vector(7 downto 0);
signal MAC_RX_EN_IN		: std_logic;
signal MAC_RX_FIFO_ERR_IN	: std_logic;
signal MAC_RX_FIFO_FULL_OUT	: std_logic;
signal MAC_RX_STAT_EN_IN	: std_logic;
signal MAC_RX_STAT_VEC_IN	: std_logic_vector(31 downto 0);
signal FR_Q_OUT			: std_logic_vector(8 downto 0);
signal FR_RD_EN_IN		: std_logic;
signal FR_FRAME_VALID_OUT	: std_logic;
signal FR_GET_FRAME_IN		: std_logic;
signal FR_FRAME_SIZE_OUT	: std_logic_vector(15 downto 0);
signal FR_FRAME_PROTO_OUT	: std_logic_vector(15 downto 0);
signal DEBUG_OUT		: std_logic_vector(63 downto 0);
signal	FR_ALLOWED_TYPES_IN	: std_logic_vector(31 downto 0);

signal	RC_RD_EN_IN		: std_logic;
signal	RC_Q_OUT		: std_logic_vector(8 downto 0);
signal	RC_FRAME_WAITING_OUT	: std_logic;
signal	RC_LOADING_DONE_IN	: std_logic;
signal	RC_FRAME_SIZE_OUT	: std_logic_vector(15 downto 0);
signal	FRAMES_RECEIVED_OUT	: std_logic_vector(31 downto 0);
signal	BYTES_RECEIVED_OUT	: std_logic_vector(31 downto 0);

signal MC_TRANSMIT_CTRL_OUT     : std_logic;
signal MC_TRANSMIT_DATA_OUT     : std_logic;
signal MC_DATA_OUT              : std_logic_vector(8 downto 0);
signal MC_RD_EN_IN              : std_logic;
signal MC_FRAME_SIZE_OUT        : std_logic_vector(15 downto 0);
signal MC_BUSY_IN               : std_logic;
signal MC_TRANSMIT_DONE_IN      : std_logic;
signal RC_FRAME_PROTO_OUT	: std_logic_vector(c_MAX_PROTOCOLS - 1 downto 0);

begin

receiver : trb_net16_gbe_frame_receiver
port map (
	CLK			=> CLK,
	RESET			=> RESET,
	LINK_OK_IN              => LINK_OK_IN,
	ALLOW_RX_IN		=> ALLOW_RX_IN,
	RX_MAC_CLK		=> RX_MAC_CLK,

	MAC_RX_EOF_IN		=> MAC_RX_EOF_IN,
	MAC_RX_ER_IN		=> MAC_RX_ER_IN,
	MAC_RXD_IN		=> MAC_RXD_IN,
	MAC_RX_EN_IN		=> MAC_RX_EN_IN,
	MAC_RX_FIFO_ERR_IN	=> MAC_RX_FIFO_ERR_IN,
	MAC_RX_FIFO_FULL_OUT	=> MAC_RX_FIFO_FULL_OUT,
	MAC_RX_STAT_EN_IN	=> MAC_RX_STAT_EN_IN,
	MAC_RX_STAT_VEC_IN	=> MAC_RX_STAT_VEC_IN,

	FR_Q_OUT		=> FR_Q_OUT,
	FR_RD_EN_IN		=> FR_RD_EN_IN,
	FR_FRAME_VALID_OUT	=> FR_FRAME_VALID_OUT,
	FR_GET_FRAME_IN		=> FR_GET_FRAME_IN,
	FR_FRAME_SIZE_OUT	=> FR_FRAME_SIZE_OUT,
	FR_FRAME_PROTO_OUT	=> FR_FRAME_PROTO_OUT,
	FR_ALLOWED_TYPES_IN     => FR_ALLOWED_TYPES_IN,

	DEBUG_OUT		=> DEBUG_OUT
);

receive_controler : trb_net16_gbe_receive_control
port map(
	CLK			=> CLK,
	RESET			=> RESET,

-- signals to/from frame_receiver
	RC_DATA_IN		=> FR_Q_OUT,
	FR_RD_EN_OUT		=> FR_RD_EN_IN,
	FR_FRAME_VALID_IN	=> FR_FRAME_VALID_OUT,
	FR_GET_FRAME_OUT	=> FR_GET_FRAME_IN,
	FR_FRAME_SIZE_IN	=> FR_FRAME_SIZE_OUT,
	FR_FRAME_PROTO_IN	=> FR_FRAME_PROTO_OUT,

-- signals to/from main controller
	RC_RD_EN_IN		=> RC_RD_EN_IN,
	RC_Q_OUT		=> RC_Q_OUT,
	RC_FRAME_WAITING_OUT	=> RC_FRAME_WAITING_OUT,
	RC_LOADING_DONE_IN	=> RC_LOADING_DONE_IN,
	RC_FRAME_SIZE_OUT	=> RC_FRAME_SIZE_OUT,
	RC_FRAME_PROTO_OUT	=> RC_FRAME_PROTO_OUT,

-- statistics
	FRAMES_RECEIVED_OUT	=> open,
	BYTES_RECEIVED_OUT	=> open,

	DEBUG_OUT		=> open
);

main_controller : trb_net16_gbe_main_control
port map (
	CLK			=> CLK,
	CLK_125			=> RX_MAC_CLK,
	RESET			=> RESET,

	MC_LINK_OK_OUT		=> open,
	MC_RESET_LINK_IN	=> '0',

-- signals to/from receive controller
	RC_FRAME_WAITING_IN	=> RC_FRAME_WAITING_OUT,
	RC_LOADING_DONE_OUT	=> RC_LOADING_DONE_IN,
	RC_DATA_IN		=> RC_Q_OUT,
	RC_RD_EN_OUT		=> RC_RD_EN_IN,
	RC_FRAME_SIZE_IN	=> RC_FRAME_SIZE_OUT,
	RC_FRAME_PROTO_IN	=> RC_FRAME_PROTO_OUT,

-- signals to/from transmit controller
	TC_TRANSMIT_CTRL_OUT	=> MC_TRANSMIT_CTRL_OUT,
	TC_TRANSMIT_DATA_OUT	=> MC_TRANSMIT_DATA_OUT,
	TC_DATA_OUT		=> MC_DATA_OUT,
	TC_RD_EN_IN		=> MC_RD_EN_IN,
	TC_FRAME_SIZE_OUT	=> MC_FRAME_SIZE_OUT,
	TC_BUSY_IN		=> MC_BUSY_IN,
	TC_TRANSMIT_DONE_IN	=> MC_TRANSMIT_DONE_IN,

-- signals to/from packet constructor
	PC_READY_IN		=> '1',
	PC_TRANSMIT_ON_IN	=> '0',
	PC_SOD_IN		=> '0',

-- signals to/from sgmii/gbe pcs_an_complete
	PCS_AN_COMPLETE_IN	=> '1',

-- signals to/from hub

-- signal to/from Host interface of TriSpeed MAC
	TSM_HADDR_OUT		=> open,
	TSM_HDATA_OUT		=> open,
	TSM_HCS_N_OUT		=> open,
	TSM_HWRITE_N_OUT	=> open,
	TSM_HREAD_N_OUT		=> open,
	TSM_HREADY_N_IN		=> '0',
	TSM_HDATA_EN_N_IN	=> '1',

	DEBUG_OUT		=> open
);

transmit_controller : trb_net16_gbe_transmit_control
port map(
	CLK			=> CLK,
	RESET			=> RESET,

-- signals to/from packet constructor
	PC_READY_IN		=> '1',
	PC_DATA_IN		=> (others => '0'),
	PC_WR_EN_IN		=> '0',
	PC_IP_SIZE_IN		=> (others => '0'),
	PC_UDP_SIZE_IN		=> (others => '0'),
	PC_FLAGS_OFFSET_IN	=> (others => '0'),
	PC_SOD_IN		=> '0',
	PC_EOD_IN		=> '0',
	PC_FC_READY_OUT		=> open,
	PC_FC_H_READY_OUT	=> open,
	PC_TRANSMIT_ON_IN	=> '0',

      -- signals from ip_configurator used by packet constructor
	IC_DEST_MAC_ADDRESS_IN  => x"112233445566",
	IC_DEST_IP_ADDRESS_IN   => x"aabbccdd",
	IC_DEST_UDP_PORT_IN     => x"0101",
	IC_SRC_MAC_ADDRESS_IN   => x"665544332211",
	IC_SRC_IP_ADDRESS_IN    => x"ddccbbaa",
	IC_SRC_UDP_PORT_IN      => x"0202",

-- signal to/from main controller
	MC_TRANSMIT_CTRL_IN	=> MC_TRANSMIT_CTRL_OUT,
	MC_TRANSMIT_DATA_IN	=> MC_TRANSMIT_DATA_OUT,
	MC_DATA_IN		=> MC_DATA_OUT,
	MC_RD_EN_OUT		=> MC_RD_EN_IN,
	MC_FRAME_SIZE_IN	=> MC_FRAME_SIZE_OUT,
	MC_BUSY_OUT		=> MC_BUSY_IN,
	MC_TRANSMIT_DONE_OUT	=> MC_TRANSMIT_DONE_IN,

-- signal to/from frame constructor
	FC_DATA_OUT		=> open,
	FC_WR_EN_OUT		=> open,
	FC_READY_IN		=> '1',
	FC_H_READY_IN		=> '1',
	FC_IP_SIZE_OUT		=> open,
	FC_UDP_SIZE_OUT		=> open,
	FC_IDENT_OUT		=> open,
	FC_FLAGS_OFFSET_OUT	=> open,
	FC_SOD_OUT		=> open,
	FC_EOD_OUT		=> open,

	DEST_MAC_ADDRESS_OUT    => open,
	DEST_IP_ADDRESS_OUT     => open,
	DEST_UDP_PORT_OUT       => open,
	SRC_MAC_ADDRESS_OUT     => open,
	SRC_IP_ADDRESS_OUT      => open,
	SRC_UDP_PORT_OUT        => open,

	DEBUG_OUT		=> open
);

-- 100 MHz system clock
CLOCK_GEN_PROC: process
begin
	CLK <= '1'; wait for 5.0 ns;
	CLK <= '0'; wait for 5.0 ns;
end process CLOCK_GEN_PROC;

-- 125 MHz MAC clock
CLOCK2_GEN_PROC: process
begin
	RX_MAC_CLK <= '1'; wait for 3.0 ns;
	RX_MAC_CLK <= '0'; wait for 4.0 ns;
end process CLOCK2_GEN_PROC;

TESTBENCH_PROC : process
begin

	wait for 50 ns;
	RESET <= '1';
	
	LINK_OK_IN  <= '1';
	ALLOW_RX_IN <= '1';
	
	MAC_RX_EOF_IN		<= '0';
	MAC_RX_ER_IN		<= '0';
	MAC_RXD_IN		<= x"00";
	MAC_RX_EN_IN		<= '0';
	MAC_RX_FIFO_ERR_IN	<= '0';
	FR_ALLOWED_TYPES_IN     <= x"0000_0003";
	
	wait for 10 ns;
	RESET <= '0';
	wait for 50 ns;

-- FIRST FRAME (invalid frame type)	
	wait until rising_edge(RX_MAC_CLK);
	MAC_RX_EN_IN <= '1';
-- dest mac
	MAC_RXD_IN		<= x"00";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"11";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"22";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"33";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"44";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"55";
	wait until rising_edge(RX_MAC_CLK);
-- src mac
	MAC_RXD_IN		<= x"00";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"11";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"22";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"33";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"44";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"55";
	wait until rising_edge(RX_MAC_CLK);
-- frame type
	MAC_RXD_IN		<= x"00";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"11";
	wait until rising_edge(RX_MAC_CLK);
-- data
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
-- cs
	MAC_RXD_IN		<= x"01";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"02";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"03";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"04";
	MAC_RX_EOF_IN <= '1';
	
	wait until rising_edge(RX_MAC_CLK);
	MAC_RX_EN_IN <='0';
	MAC_RX_EOF_IN <= '0';
	
	
	wait for 100 ns;
	
-- SECOND FRAME	
	wait until rising_edge(RX_MAC_CLK);
	MAC_RX_EN_IN <= '1';
-- dest mac
	MAC_RXD_IN		<= x"00";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"11";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"22";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"33";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"44";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"55";
	wait until rising_edge(RX_MAC_CLK);
-- src mac
	MAC_RXD_IN		<= x"00";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"11";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"22";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"33";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"44";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"55";
	wait until rising_edge(RX_MAC_CLK);
-- frame type
	MAC_RXD_IN		<= x"08";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"00";
	wait until rising_edge(RX_MAC_CLK);
-- data
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
-- cs
	MAC_RXD_IN		<= x"01";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"02";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"03";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"04";
	MAC_RX_EOF_IN <= '1';

	wait until rising_edge(RX_MAC_CLK);
	MAC_RX_EN_IN <='0';
	MAC_RX_EOF_IN <= '0';
	
	
	wait for 50 ns;
	
-- THIRD FRAME	
	wait until rising_edge(RX_MAC_CLK);
	MAC_RX_EN_IN <= '1';
-- dest mac
	MAC_RXD_IN		<= x"00";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"11";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"22";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"33";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"44";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"55";
	wait until rising_edge(RX_MAC_CLK);
-- src mac
	MAC_RXD_IN		<= x"00";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"11";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"22";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"33";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"44";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"55";
	wait until rising_edge(RX_MAC_CLK);
-- frame type
	MAC_RXD_IN		<= x"08";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"06";
	wait until rising_edge(RX_MAC_CLK);
-- data
	MAC_RXD_IN		<= x"aa";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"bb";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"cc";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"dd";
	wait until rising_edge(RX_MAC_CLK);
-- cs
	MAC_RXD_IN		<= x"01";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"02";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"03";
	wait until rising_edge(RX_MAC_CLK);
	MAC_RXD_IN		<= x"04";
	MAC_RX_EOF_IN <= '1';

	wait until rising_edge(RX_MAC_CLK);
	MAC_RX_EN_IN <='0';
	MAC_RX_EOF_IN <= '0';
	
	wait for 100 ns;
	
	
	wait;

end process;


end architecture;
