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
-- controller has to control the rest of the logic (TX part, TS_MAC, HUB) accordingly to 
-- the message received from receiver, frame checking is already done
-- 


entity trb_net16_gbe_receive_control is
port (
	CLK			: in	std_logic;  -- system clock
	RESET			: in	std_logic;

-- signals to/from frame_receiver
	RC_DATA_IN		: in	std_logic_vector(8 downto 0);
	FR_RD_EN_OUT		: out	std_logic;
	FR_FRAME_VALID_IN	: in	std_logic;
	FR_GET_FRAME_OUT	: out	std_logic;
	FR_FRAME_SIZE_IN	: in	std_logic_vector(15 downto 0);
	FR_FRAME_PROTO_IN	: in	std_logic_vector(15 downto 0);
	FR_IP_PROTOCOL_IN	: in	std_logic_vector(7 downto 0);
	
	FR_SRC_MAC_ADDRESS_IN	: in	std_logic_vector(47 downto 0);
	FR_DEST_MAC_ADDRESS_IN  : in	std_logic_vector(47 downto 0);
	FR_SRC_IP_ADDRESS_IN	: in	std_logic_vector(31 downto 0);
	FR_DEST_IP_ADDRESS_IN	: in	std_logic_vector(31 downto 0);
	FR_SRC_UDP_PORT_IN	: in	std_logic_vector(15 downto 0);
	FR_DEST_UDP_PORT_IN	: in	std_logic_vector(15 downto 0);


-- signals to/from main controller
	RC_RD_EN_IN		: in	std_logic;
	RC_Q_OUT		: out	std_logic_vector(8 downto 0);
	RC_FRAME_WAITING_OUT	: out	std_logic;
	RC_LOADING_DONE_IN	: in	std_logic;
	RC_FRAME_SIZE_OUT	: out	std_logic_vector(15 downto 0);
	RC_FRAME_PROTO_OUT	: out	std_logic_vector(c_MAX_PROTOCOLS - 1 downto 0);

	RC_SRC_MAC_ADDRESS_OUT	: out	std_logic_vector(47 downto 0);
	RC_DEST_MAC_ADDRESS_OUT : out	std_logic_vector(47 downto 0);
	RC_SRC_IP_ADDRESS_OUT	: out	std_logic_vector(31 downto 0);
	RC_DEST_IP_ADDRESS_OUT	: out	std_logic_vector(31 downto 0);
	RC_SRC_UDP_PORT_OUT	: out	std_logic_vector(15 downto 0);
	RC_DEST_UDP_PORT_OUT	: out	std_logic_vector(15 downto 0);

-- statistics
	FRAMES_RECEIVED_OUT	: out	std_logic_vector(31 downto 0);
	BYTES_RECEIVED_OUT	: out	std_logic_vector(31 downto 0);

	DEBUG_OUT		: out	std_logic_vector(63 downto 0)
);
end trb_net16_gbe_receive_control;


architecture trb_net16_gbe_receive_control of trb_net16_gbe_receive_control is

--attribute HGROUP : string;
--attribute HGROUP of trb_net16_gbe_receive_control : architecture is "GBE_MAIN_group";

type load_states is (IDLE, PREPARE, READY);
signal load_current_state, load_next_state : load_states;

signal frames_received_ctr       : std_logic_vector(31 downto 0);
signal frames_readout_ctr        : std_logic_vector(31 downto 0);
signal bytes_rec_ctr             : std_logic_vector(31 downto 0);

signal state                     : std_logic_vector(3 downto 0);
signal proto_code                : std_logic_vector(c_MAX_PROTOCOLS - 1 downto 0);
signal reset_prioritizer         : std_logic;

-- debug only
signal saved_proto               : std_logic_vector(2 downto 0);

begin

FR_RD_EN_OUT            <= RC_RD_EN_IN;
RC_Q_OUT                <= RC_DATA_IN;
RC_FRAME_SIZE_OUT       <= FR_FRAME_SIZE_IN;
RC_SRC_MAC_ADDRESS_OUT  <= FR_SRC_MAC_ADDRESS_IN;
RC_DEST_MAC_ADDRESS_OUT <= FR_DEST_MAC_ADDRESS_IN;
RC_SRC_IP_ADDRESS_OUT   <= FR_SRC_IP_ADDRESS_IN;
RC_DEST_IP_ADDRESS_OUT  <= FR_DEST_IP_ADDRESS_IN;
RC_SRC_UDP_PORT_OUT     <= FR_SRC_UDP_PORT_IN;
RC_DEST_UDP_PORT_OUT    <= FR_DEST_UDP_PORT_IN;

protocol_prioritizer : trb_net16_gbe_protocol_prioritizer
port map(
	CLK			=> CLK,
	RESET			=> reset_prioritizer,
	
	FRAME_TYPE_IN		=> FR_FRAME_PROTO_IN,
	PROTOCOL_CODE_IN	=> FR_IP_PROTOCOL_IN,
	UDP_PROTOCOL_IN		=> FR_DEST_UDP_PORT_IN,
	
	CODE_OUT		=> proto_code
);

reset_prioritizer <= '1' when load_current_state = IDLE else '0';

--RC_FRAME_PROTO_OUT <= proto_code when (and_all(proto_code) = '0') else (others => '0');
RC_FRAME_PROTO_OUT <= proto_code;  -- no more ones as the incorrect value, last slot for Trash

DEBUG_OUT(3 downto 0)   <= state;
DEBUG_OUT(11 downto 4)  <= frames_received_ctr(7 downto 0);
DEBUG_OUT(19 downto 12) <= frames_readout_ctr(7 downto 0);
DEBUG_OUT(31 downto 20) <= bytes_rec_ctr(11 downto 0);

LOAD_MACHINE_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    if (RESET = '1') then
      load_current_state <= IDLE;
    else
      load_current_state <= load_next_state;
    end if;
  end if;
end process LOAD_MACHINE_PROC;

LOAD_MACHINE : process(load_current_state, frames_readout_ctr, frames_received_ctr, RC_LOADING_DONE_IN)
begin
  case load_current_state is

    when IDLE =>
      state <= x"1";
      if (frames_readout_ctr /= frames_received_ctr) then -- frame is still waiting in frame_receiver
	load_next_state <= PREPARE;
      else
	load_next_state <= IDLE;
      end if;

    when PREPARE =>  -- prepare frame size
      state <= x"2";
      load_next_state <= READY;

    when READY => -- wait for reading out the whole frame
      state <= x"3";
      if (RC_LOADING_DONE_IN = '1') then
	load_next_state <= IDLE;
      else
	load_next_state <= READY;
      end if;

  end case;
end process LOAD_MACHINE;

FR_GET_FRAME_OUT <= '1' when (load_current_state = PREPARE)
		  else '0';

RC_FRAME_WAITING_OUT <= '1' when (load_current_state = READY)
		      else '0';

SYNC_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    FRAMES_RECEIVED_OUT              <= frames_received_ctr;
    --BYTES_RECEIVED_OUT               <= bytes_rec_ctr;
    BYTES_RECEIVED_OUT(15 downto 0)  <= bytes_rec_ctr(15 downto 0);
    BYTES_RECEIVED_OUT(18 downto 16) <= saved_proto;
    BYTES_RECEIVED_OUT(31 downto 19) <= (others => '0');
  end if;
end process SYNC_PROC;

FRAMES_REC_CTR_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    if (RESET = '1') then
      frames_received_ctr <= (others => '0');
    elsif (FR_FRAME_VALID_IN = '1') then
      frames_received_ctr <= frames_received_ctr + x"1";
    end if;
  end if;
end process FRAMES_REC_CTR_PROC;

FRAMES_READOUT_CTR_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    if (RESET = '1') then
      frames_readout_ctr <= (others => '0');
    elsif (RC_LOADING_DONE_IN = '1') then
      frames_readout_ctr <= frames_readout_ctr + x"1";
    end if;    
  end if;
end process FRAMES_READOUT_CTR_PROC;

BYTES_REC_CTR_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    if (RESET = '1') then
      bytes_rec_ctr <= (others => '0');
    elsif (FR_FRAME_VALID_IN = '1') then
      bytes_rec_ctr <= bytes_rec_ctr + FR_FRAME_SIZE_IN;    
    end if;
  end if;
end process BYTES_REC_CTR_PROC;

-- debug only
SAVED_PROTO_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			saved_proto <= (others => '0');
		elsif (load_current_state = READY) then
			if (and_all(proto_code) = '0') then
				saved_proto <= proto_code;
			else
				saved_proto <= (others => '0');
			end if;
		end if;
	end if;
end process SAVED_PROTO_PROC;
-- end of debug


end trb_net16_gbe_receive_control;


