LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;
use work.trb_net16_hub_func.all;

--********
-- configures TriSpeed MAC and signalizes when it's ready
-- used also to filter out frames with different addresses
-- after main configuration (by setting TsMAC filtering accordingly)



entity trb_net16_gbe_mac_control is
port (
	CLK			: in	std_logic;  -- system clock
	RESET			: in	std_logic;

-- signals to/from main controller
	MC_TSMAC_READY_OUT	: out	std_logic;
	MC_RECONF_IN		: in	std_logic;
	MC_GBE_EN_IN		: in	std_logic;
	MC_RX_DISCARD_FCS	: in	std_logic;
	MC_PROMISC_IN		: in	std_logic;
	MC_MAC_ADDR_IN		: in	std_logic_vector(47 downto 0);

-- signal to/from Host interface of TriSpeed MAC
	TSM_HADDR_OUT		: out	std_logic_vector(7 downto 0);
	TSM_HDATA_OUT		: out	std_logic_vector(7 downto 0);
	TSM_HCS_N_OUT		: out	std_logic;
	TSM_HWRITE_N_OUT	: out	std_logic;
	TSM_HREAD_N_OUT		: out	std_logic;
	TSM_HREADY_N_IN		: in	std_logic;
	TSM_HDATA_EN_N_IN	: in	std_logic;

	DEBUG_OUT		: out	std_logic_vector(63 downto 0)
);
end trb_net16_gbe_mac_control;


architecture trb_net16_gbe_mac_control of trb_net16_gbe_mac_control is

--attribute HGROUP : string;
--attribute HGROUP of trb_net16_gbe_mac_control : architecture is "GBE_BUF_group";

type mac_conf_states is (IDLE, DISABLE, WRITE_TX_RX_CTRL, WRITE_MAX_PKT_SIZE, SKIP, WRITE_IPG, 
			  WRITE_MAC0, WRITE_MAC1, WRITE_MAC2, ENABLE, READY);
signal mac_conf_current_state, mac_conf_next_state : mac_conf_states;

signal tsmac_ready                          : std_logic;
signal reg_mode                             : std_logic_vector(15 downto 0);
signal reg_tx_rx_ctrl                       : std_logic_vector(15 downto 0);
signal reg_max_pkt_size                     : std_logic_vector(15 downto 0);
signal reg_ipg                              : std_logic_vector(15 downto 0);
signal reg_mac0                             : std_logic_vector(15 downto 0);
signal reg_mac1                             : std_logic_vector(15 downto 0);
signal reg_mac2                             : std_logic_vector(15 downto 0);

signal haddr                                : std_logic_vector(7 downto 0);
signal hcs_n                                : std_logic;
signal hwrite_n                             : std_logic;
signal hdata_pointer                        : integer range 0 to 1;
signal state                                : std_logic_vector(3 downto 0);
signal hready_n_q                           : std_logic;

begin

DEBUG_OUT(3 downto 0)   <= state;
DEBUG_OUT(7 downto 4)   <= haddr(3 downto 0);
DEBUG_OUT(8)            <= hcs_n;
DEBUG_OUT(9)            <= hwrite_n;
DEBUG_OUT(63 downto 11) <= (others => '0');

reg_mode(15 downto 4) <= (others => '0'); -- reserved
reg_mode(3)           <= '1'; -- tx_en
reg_mode(2)           <= '1'; -- rx_en
reg_mode(1)           <= '1'; -- flow_control en
reg_mode(0)           <= MC_GBE_EN_IN; -- gbe en

reg_tx_rx_ctrl(15 downto 9) <= (others => '0'); -- reserved
reg_tx_rx_ctrl(8)           <= '1'; -- receive short
reg_tx_rx_ctrl(7)           <= '1'; -- receive broadcast
reg_tx_rx_ctrl(6)           <= '1'; -- drop control
reg_tx_rx_ctrl(5)           <= '0'; -- half_duplex en 
reg_tx_rx_ctrl(4)           <= '1'; -- receive multicast
reg_tx_rx_ctrl(3)           <= '1'; -- receive pause
reg_tx_rx_ctrl(2)           <= '0'; -- transmit disable FCS
reg_tx_rx_ctrl(1)           <= '1'; -- receive discard FCS and padding
reg_tx_rx_ctrl(0)           <= MC_PROMISC_IN; -- promiscuous mode

reg_max_pkt_size(15 downto 0) <= x"05EE";  -- 1518 default value

reg_ipg(15 downto 5) <= (others => '0');
reg_ipg(4 downto 0)  <= "01100"; -- default value inter-packet-gap in byte time

reg_mac0(7 downto 0)  <= MC_MAC_ADDR_IN(7 downto 0);
reg_mac0(15 downto 8) <= MC_MAC_ADDR_IN(15 downto 8);
reg_mac1(7 downto 0)  <= MC_MAC_ADDR_IN(23 downto 16);
reg_mac1(15 downto 8) <= MC_MAC_ADDR_IN(31 downto 24);
reg_mac2(7 downto 0)  <= MC_MAC_ADDR_IN(39 downto 32);
reg_mac2(15 downto 8) <= MC_MAC_ADDR_IN(47 downto 40);


MAC_CONF_MACHINE_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    if (RESET = '1') or (MC_RECONF_IN = '1') then
      mac_conf_current_state <= IDLE;
    else
      mac_conf_current_state <= mac_conf_next_state;
    end if;
  end if;
end process MAC_CONF_MACHINE_PROC;

MAC_CONF_MACHINE : process(mac_conf_current_state, tsmac_ready, haddr)
begin

  case mac_conf_current_state is

    when IDLE =>
      state <= x"1";
      if (tsmac_ready = '0') then
	mac_conf_next_state <= DISABLE;
      else
	mac_conf_next_state <= IDLE;
      end if;

    when DISABLE =>
      state <= x"2";
      if (haddr = x"01") then
	mac_conf_next_state <= WRITE_TX_RX_CTRL;
      else
	mac_conf_next_state <= DISABLE;
      end if;

    when WRITE_TX_RX_CTRL =>
      state <= x"3";
      if (haddr = x"03") then
	mac_conf_next_state <= WRITE_MAX_PKT_SIZE;
      else
	mac_conf_next_state <= WRITE_TX_RX_CTRL;
      end if;

    when WRITE_MAX_PKT_SIZE =>
      state <= x"4";
      if (haddr = x"05") then
	mac_conf_next_state <= SKIP;
      else
	mac_conf_next_state <= WRITE_MAX_PKT_SIZE;
      end if;

    when SKIP =>
      state <= x"5";
      if (haddr = x"07") then
	mac_conf_next_state <= WRITE_IPG;
      else
	mac_conf_next_state <= SKIP;
      end if;

    when WRITE_IPG =>
      state <= x"6";
      if (haddr = x"09") then
	mac_conf_next_state <= WRITE_MAC0;
      else
	mac_conf_next_state <= WRITE_IPG;
      end if;	

    when WRITE_MAC0 =>
      state <= x"7";
      if (haddr = x"0B") then
	mac_conf_next_state <= WRITE_MAC1;
      else
	mac_conf_next_state <= WRITE_MAC0;
      end if;

    when WRITE_MAC1 =>
      state <= x"8";
      if (haddr = x"0D") then
	mac_conf_next_state <= WRITE_MAC2;
      else
	mac_conf_next_state <= WRITE_MAC1;
      end if;

    when WRITE_MAC2 =>
      state <= x"9";
      if (haddr = x"0F") then
	mac_conf_next_state <= ENABLE;
      else
	mac_conf_next_state <= WRITE_MAC2;
      end if;

    when ENABLE =>
      state <= x"a";
      if (haddr = x"01") then
	mac_conf_next_state <= READY;
      else
	mac_conf_next_state <= ENABLE;
      end if;

    when READY =>
      state <= x"b";
      if (MC_RECONF_IN = '1') then
	mac_conf_next_state <= IDLE;
      else
	mac_conf_next_state <= READY;
      end if;

  end case;

end process MAC_CONF_MACHINE;

HADDR_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    if (RESET = '1') or (mac_conf_current_state = IDLE) then
      haddr <= (others => '0');
    elsif (mac_conf_current_state /= IDLE) and (hcs_n = '0') and (TSM_HREADY_N_IN = '0') then
      haddr <= haddr + x"1";
    elsif (mac_conf_current_state = SKIP) then
      haddr <= haddr + x"1";
    elsif (mac_conf_current_state = WRITE_MAC2) and (haddr = x"0F") and (TSM_HREADY_N_IN = '0') then
      haddr <= (others => '0');
    end if;
  end if;
end process HADDR_PROC;

HDATA_PROC : process(mac_conf_current_state)
begin

  case mac_conf_current_state is

    when WRITE_TX_RX_CTRL =>
      TSM_HDATA_OUT <= reg_tx_rx_ctrl(7 + 8 * hdata_pointer downto 8 * hdata_pointer);

    when WRITE_MAX_PKT_SIZE =>
      TSM_HDATA_OUT <= reg_max_pkt_size(7 + 8 * hdata_pointer downto 8 * hdata_pointer);

    when WRITE_IPG =>
      TSM_HDATA_OUT <= reg_ipg(7 + 8 * hdata_pointer downto 8 * hdata_pointer);

    when WRITE_MAC0 =>
      TSM_HDATA_OUT <= reg_mac0(7 + 8 * hdata_pointer downto 8 * hdata_pointer);

    when WRITE_MAC1 =>
      TSM_HDATA_OUT <= reg_mac1(7 + 8 * hdata_pointer downto 8 * hdata_pointer);

    when WRITE_MAC2 =>
      TSM_HDATA_OUT <= reg_mac2(7 + 8 * hdata_pointer downto 8 * hdata_pointer);

    when ENABLE =>
      TSM_HDATA_OUT <= reg_mode(7 + 8 * hdata_pointer downto 8 * hdata_pointer);

    when others =>
      TSM_HDATA_OUT <= (others => '0');

  end case;

end process HDATA_PROC;

-- delay hready by one clock cycle to keep hcs and hwrite active during hready
HREADY_Q_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    hready_n_q <= TSM_HREADY_N_IN;
  end if;
end process HREADY_Q_PROC;

hdata_pointer <= 1 when haddr(0) = '1' else 0;

hcs_n       <= '0' when (mac_conf_current_state /= IDLE) and (mac_conf_current_state /= SKIP) and (mac_conf_current_state /= READY) and (hready_n_q = '1')
	    else '1';  -- should also support reading

hwrite_n    <= hcs_n when (mac_conf_current_state /= IDLE) else '1'; -- active only during writing

tsmac_ready <= '1' when (mac_conf_current_state = READY) else '0';

TSM_HADDR_OUT      <= haddr;
TSM_HCS_N_OUT      <= hcs_n;
TSM_HWRITE_N_OUT   <= hwrite_n;
TSM_HREAD_N_OUT    <= '1';  -- for the moment no reading
MC_TSMAC_READY_OUT <= tsmac_ready;


end trb_net16_gbe_mac_control;


