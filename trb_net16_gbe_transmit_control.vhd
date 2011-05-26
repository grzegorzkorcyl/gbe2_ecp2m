LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;
use work.trb_net16_hub_func.all;

--********
-- multiplexes the output stream between data and slow control frames
-- creates slow control frames

entity trb_net16_gbe_transmit_control is
port (
	CLK			: in	std_logic;  -- system clock
	RESET			: in	std_logic;

-- signals to/from packet constructor
	PC_READY_IN		: in	std_logic;
	PC_DATA_IN		: in	std_logic_vector(7 downto 0);
	PC_WR_EN_IN		: in	std_logic;
	PC_IP_SIZE_IN		: in	std_logic_vector(15 downto 0);
	PC_UDP_SIZE_IN		: in	std_logic_vector(15 downto 0);
	PC_FLAGS_OFFSET_IN	: in	std_logic_vector(15 downto 0);
	PC_SOD_IN		: in	std_logic;
	PC_EOD_IN		: in	std_logic;
	PC_FC_READY_OUT		: out	std_logic;
	PC_FC_H_READY_OUT	: out	std_logic;
	PC_TRANSMIT_ON_IN	: in	std_logic;

      -- signals from ip_configurator used by packet constructor
	IC_DEST_MAC_ADDRESS_IN     : in    std_logic_vector(47 downto 0);
	IC_DEST_IP_ADDRESS_IN      : in    std_logic_vector(31 downto 0);
	IC_DEST_UDP_PORT_IN        : in    std_logic_vector(15 downto 0);
	IC_SRC_MAC_ADDRESS_IN      : in    std_logic_vector(47 downto 0);
	IC_SRC_IP_ADDRESS_IN       : in    std_logic_vector(31 downto 0);
	IC_SRC_UDP_PORT_IN         : in    std_logic_vector(15 downto 0);

-- signal to/from main controller
	MC_TRANSMIT_CTRL_IN	: in	std_logic;  -- slow control frame is waiting to be built and sent
	MC_TRANSMIT_DATA_IN	: in	std_logic;
	MC_DATA_IN		: in	std_logic_vector(8 downto 0);
	MC_RD_EN_OUT		: out	std_logic;
	MC_FRAME_SIZE_IN	: in	std_logic_vector(15 downto 0);
	MC_FRAME_TYPE_IN	: in	std_logic_vector(15 downto 0);
	MC_BUSY_OUT		: out	std_logic;
	MC_TRANSMIT_DONE_OUT	: out	std_logic;

-- signal to/from frame constructor
	FC_DATA_OUT		: out	std_logic_vector(7 downto 0);
	FC_WR_EN_OUT		: out	std_logic;
	FC_READY_IN		: in	std_logic;
	FC_H_READY_IN		: in	std_logic;
	FC_FRAME_TYPE_OUT	: out	std_logic_vector(15 downto 0);
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
end trb_net16_gbe_transmit_control;


architecture trb_net16_gbe_transmit_control of trb_net16_gbe_transmit_control is

-- attribute HGROUP : string;
-- attribute HGROUP of trb_net16_gbe_frame_receiver : architecture is "GBE_main_ctrl";

attribute syn_encoding	: string;

type tx_states is (IDLE, TRANSMIT_DATA, TRANSMIT_CTRL, CLEANUP);
signal tx_current_state, tx_next_state : tx_states;
attribute syn_encoding of tx_current_state: signal is "safe,gray";

type ctrl_construct_states is (IDLE, WAIT_FOR_FC, LOAD_DATA, CLOSE, CLEANUP);
signal ctrl_construct_current_state, ctrl_construct_next_state : ctrl_construct_states;
attribute syn_encoding of ctrl_construct_current_state: signal is "safe,gray";

signal ctrl_sod                                 : std_logic;
signal delayed_wr_en                            : std_logic;
signal delayed_wr_en_q                          : std_logic;
signal sent_bytes_ctr                           : std_logic_vector(15 downto 0);
signal sent_packets_ctr                         : std_logic_vector(15 downto 0);

signal state                                    : std_logic_vector(3 downto 0);
signal state2                                   : std_logic_vector(3 downto 0);

begin

DEBUG_OUT(3 downto 0) <= state;
DEBUG_OUT(7 downto 4) <= state2;
DEBUG_OUT(31 downto 8) <= (others => '0');

MC_BUSY_OUT <= '0' when (tx_current_state = IDLE)
	    else '1';

MC_TRANSMIT_DONE_OUT <= '1' when (tx_current_state = CLEANUP) else '0';

TX_MACHINE_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    if (RESET = '1') then
      tx_current_state <= IDLE;
    else
      tx_current_state <= tx_next_state;
    end if;
  end if;
end process TX_MACHINE_PROC;

--TX_MACHINE : process(tx_current_state, PC_SOD_IN, FC_READY_IN, MC_CTRL_FRAME_REQ_IN, PC_EOD_IN, PC_TRANSMIT_ON_IN, ctrl_construct_current_state)
TX_MACHINE : process(tx_current_state, MC_TRANSMIT_CTRL_IN, MC_TRANSMIT_DATA_IN, FC_READY_IN, PC_EOD_IN, ctrl_construct_current_state)
begin
  case tx_current_state is

    when IDLE =>
      state <= x"1";
      if (FC_READY_IN = '1') then
	--if (MC_CTRL_FRAME_REQ_IN = '1') and (PC_TRANSMIT_ON_IN = '0') then
	if (MC_TRANSMIT_DATA_IN = '1') then
	  tx_next_state <= TRANSMIT_DATA;
	--elsif (PC_SOD_IN = '1') then
	elsif (MC_TRANSMIT_CTRL_IN = '1') then
	  tx_next_state <= TRANSMIT_CTRL;
	else
	  tx_next_state <= IDLE;
	end if;
      else
	tx_next_state <= IDLE;
      end if;

    when TRANSMIT_DATA =>
      state <= x"2";
      if (PC_EOD_IN = '1') then
	tx_next_state <= CLEANUP;
      else
	tx_next_state <= TRANSMIT_DATA;
      end if;
      
    when TRANSMIT_CTRL =>
      state <= x"3";
      if (ctrl_construct_current_state = CLOSE) then
	tx_next_state <= CLEANUP;
      else
	tx_next_state <= TRANSMIT_CTRL;
      end if;

    when CLEANUP =>
      state <= x"4";
      tx_next_state <= IDLE;

  end case;
end process TX_MACHINE;

FC_FRAME_TYPE_OUT <= MC_FRAME_TYPE_IN;

SELECTOR : process(CLK)
begin
  if rising_edge(CLK) then

    case tx_current_state is
      
      when TRANSMIT_DATA =>
	FC_DATA_OUT          <= PC_DATA_IN;
	FC_SOD_OUT           <= PC_SOD_IN;
	FC_EOD_OUT           <= PC_EOD_IN;
	FC_IP_SIZE_OUT       <= PC_IP_SIZE_IN;
	FC_UDP_SIZE_OUT      <= PC_UDP_SIZE_IN;
	FC_FLAGS_OFFSET_OUT  <= PC_FLAGS_OFFSET_IN;
	FC_IDENT_OUT         <= sent_packets_ctr;

	DEST_MAC_ADDRESS_OUT <= IC_DEST_MAC_ADDRESS_IN;
	DEST_IP_ADDRESS_OUT  <= IC_DEST_IP_ADDRESS_IN;
	DEST_UDP_PORT_OUT    <= IC_DEST_UDP_PORT_IN;
	SRC_MAC_ADDRESS_OUT  <= IC_SRC_MAC_ADDRESS_IN;
	SRC_IP_ADDRESS_OUT   <= IC_SRC_IP_ADDRESS_IN;
	SRC_UDP_PORT_OUT     <= IC_SRC_UDP_PORT_IN;

      when TRANSMIT_CTRL =>
	FC_DATA_OUT         <= MC_DATA_IN(7 downto 0);

	if (ctrl_construct_current_state = WAIT_FOR_FC) and (FC_READY_IN = '1') then
	  FC_SOD_OUT        <= '1';
	else
	  FC_SOD_OUT        <= '0';
	end if;

	if (ctrl_construct_current_state = CLOSE) then
	  FC_EOD_OUT        <= '1';
	else
	  FC_EOD_OUT        <= '0';
	end if;

	
	FC_IP_SIZE_OUT      <= MC_FRAME_SIZE_IN;
	FC_UDP_SIZE_OUT     <= MC_FRAME_SIZE_IN;
	FC_FLAGS_OFFSET_OUT <= (others => '0'); -- fixed to one-frame packets

	if (ctrl_construct_current_state = WAIT_FOR_FC) and (FC_H_READY_IN = '1') then
	  MC_RD_EN_OUT  <= '1';
	  delayed_wr_en <= '0'; --'1';
	elsif (ctrl_construct_current_state = LOAD_DATA) and (sent_bytes_ctr < MC_FRAME_SIZE_IN - x"2") then -- (sent_bytes_ctr /= MC_FRAME_SIZE_IN) then
	  MC_RD_EN_OUT  <= '1';
	  delayed_wr_en <= '1';
	else
	  MC_RD_EN_OUT  <= '0';
	  delayed_wr_en <= '0';
	end if;

	DEST_MAC_ADDRESS_OUT <= x"d93bb10c0e00";
	DEST_IP_ADDRESS_OUT  <= x"0100a8c0";
	DEST_UDP_PORT_OUT    <= x"50c3";
	SRC_MAC_ADDRESS_OUT  <= x"febefebe0000";
	SRC_IP_ADDRESS_OUT   <= x"1000a8c0";
	SRC_UDP_PORT_OUT     <= x"50c3";
	FC_IDENT_OUT         <= sent_packets_ctr;

      when others =>
	MC_RD_EN_OUT        <= '0';
	FC_DATA_OUT         <= (others => '0');
	delayed_wr_en       <= '0';
	FC_SOD_OUT          <= '0';
	FC_EOD_OUT          <= '0';

    end case;

  end if;
end process SELECTOR;

FC_WR_EN_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    delayed_wr_en_q <= delayed_wr_en;

    case tx_current_state is
      when TRANSMIT_DATA =>
	FC_WR_EN_OUT <= PC_WR_EN_IN;
      when TRANSMIT_CTRL =>
	FC_WR_EN_OUT <= delayed_wr_en_q;
      when  others =>
	FC_WR_EN_OUT <= '0';
    end case;
  end if;
end process FC_WR_EN_PROC;


CTRL_CONSTRUCT_MACHINE_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    if (RESET = '1') then
      ctrl_construct_current_state <= IDLE;
    else
      ctrl_construct_current_state <= ctrl_construct_next_state;
    end if;
  end if;
end process CTRL_CONSTRUCT_MACHINE_PROC;

CTRL_CONSTRUCT_MACHINE : process(ctrl_construct_current_state, tx_current_state, FC_H_READY_IN, sent_bytes_ctr, MC_FRAME_SIZE_IN)
begin

  case ctrl_construct_current_state is

    when IDLE =>
      state2 <= x"1";
      if (tx_current_state = TRANSMIT_CTRL) then
	ctrl_construct_next_state <= WAIT_FOR_FC;
      else
	ctrl_construct_next_state <= IDLE;
      end if;

    when WAIT_FOR_FC =>
      state2 <= x"2";
      if (FC_H_READY_IN = '1') then
	ctrl_construct_next_state <= LOAD_DATA;
      else
	ctrl_construct_next_state <= WAIT_FOR_FC;
      end if;

    when LOAD_DATA =>
      state2 <= x"3";
      if (sent_bytes_ctr = MC_FRAME_SIZE_IN - x"1") then
	ctrl_construct_next_state <= CLOSE;
      else
	ctrl_construct_next_state <= LOAD_DATA; 
      end if;

    when CLOSE =>
      state2 <= x"4";
      ctrl_construct_next_state <= CLEANUP;

    when CLEANUP =>
      state2 <= x"5";
      ctrl_construct_next_state <= IDLE;

  end case;

end process CTRL_CONSTRUCT_MACHINE;

SENT_BYTES_CTR_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    if (RESET = '1') or (ctrl_construct_current_state = IDLE) then
      sent_bytes_ctr <= (others => '0');
    elsif (delayed_wr_en_q = '1') then
      sent_bytes_ctr <= sent_bytes_ctr + x"1";
    end if;
  end if;
end process SENT_BYTES_CTR_PROC;

PC_FC_H_READY_OUT   <= FC_H_READY_IN when ((tx_current_state = IDLE) or (tx_current_state = TRANSMIT_DATA))
		      else '0';

PC_FC_READY_OUT     <= FC_READY_IN   when ((tx_current_state = IDLE) or (tx_current_state = TRANSMIT_DATA))
		      else '0';

SENT_PACKETS_CTR_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    if (RESET = '1') then
      sent_packets_ctr <= (others => '0');
    elsif (tx_current_state = CLEANUP) then
      sent_packets_ctr <= sent_packets_ctr + x"1";
    end if;
  end if;
end process SENT_PACKETS_CTR_PROC;



end trb_net16_gbe_transmit_control;


