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
-- controls the work of the whole gbe in both directions
-- multiplexes the output between data stream and output slow control packets based on priority
-- reacts to incoming gbe slow control commands
-- 


entity trb_net16_gbe_main_control is
port (
	CLK			: in	std_logic;  -- system clock
	CLK_125			: in	std_logic;
	RESET			: in	std_logic;

	MC_LINK_OK_OUT		: out	std_logic;
	MC_RESET_LINK_IN	: in	std_logic;

-- signals to/from receive controller
	RC_FRAME_WAITING_IN	: in	std_logic;
	RC_LOADING_DONE_OUT	: out	std_logic;
	RC_DATA_IN		: in	std_logic_vector(8 downto 0);
	RC_RD_EN_OUT		: out	std_logic;
	RC_FRAME_SIZE_IN	: in	std_logic_vector(15 downto 0);


-- signals to/from transmit controller
	TC_TRANSMIT_CTRL_OUT	: out	std_logic;  -- slow control frame is waiting to be built and sent
	TC_TRANSMIT_DATA_OUT	: out	std_logic;
	TC_DATA_OUT		: out	std_logic_vector(8 downto 0);
	TC_RD_EN_IN		: in	std_logic;
	TC_FRAME_SIZE_OUT	: out	std_logic_vector(15 downto 0);
	TC_BUSY_IN		: in	std_logic;
	TC_TRANSMIT_DONE_IN	: in	std_logic;

-- signals to/from packet constructor
	PC_READY_IN		: in	std_logic;
	PC_TRANSMIT_ON_IN	: in	std_logic;
	PC_SOD_IN		: in	std_logic;

-- signals to/from sgmii/gbe pcs_an_complete
	PCS_AN_COMPLETE_IN	: in	std_logic;

-- signals to/from hub

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
end trb_net16_gbe_main_control;


architecture trb_net16_gbe_main_control of trb_net16_gbe_main_control is

-- attribute HGROUP : string;
-- attribute HGROUP of trb_net16_gbe_frame_receiver : architecture is "GBE_main_ctrl";

signal saved_frame_req                      : std_logic;
signal saved_frame_req_q                    : std_logic;
signal saved_frame_req_t                    : std_logic;

signal tsm_ready                            : std_logic;
signal tsm_reconf                           : std_logic;
signal tsm_haddr                            : std_logic_vector(7 downto 0);
signal tsm_hdata                            : std_logic_vector(7 downto 0);
signal tsm_hcs_n                            : std_logic;
signal tsm_hwrite_n                         : std_logic;
signal tsm_hread_n                          : std_logic;

type link_states is (ACTIVE, INACTIVE, ENABLE_MAC, TIMEOUT, FINALIZE);
signal link_current_state, link_next_state : link_states;

signal link_down_ctr                 : std_logic_vector(15 downto 0);
signal link_down_ctr_lock            : std_logic;
signal link_ok                       : std_logic;
signal link_ok_timeout_ctr           : std_logic_vector(15 downto 0);

signal mac_control_debug             : std_logic_vector(63 downto 0);

type flow_states is (IDLE, TRANSMIT_DATA, TRANSMIT_CTRL, CLEANUP);
signal flow_current_state, flow_next_state : flow_states;

signal state                        : std_logic_vector(3 downto 0);

begin

--TC_CTRL_FRAME_REQ_OUT <= RC_FRAME_READY_IN;

DEBUG_OUT(3 downto 0)  <= state;
DEBUG_OUT(31 downto 4) <= (others => '0');


TC_DATA_OUT  <= RC_DATA_IN;

TC_FRAME_SIZE_OUT <= RC_FRAME_SIZE_IN;

RC_RD_EN_OUT <= TC_RD_EN_IN;



--*********************
--	DATA FLOW CONTROL

FLOW_MACHINE_PROC : process(CLK)
begin
  if rising_edge(CLK) then
    if (RESET = '1') then
      flow_current_state <= IDLE;
    else
      flow_current_state <= flow_next_state;
    end if;
  end if;
end process FLOW_MACHINE_PROC;

FLOW_MACHINE : process(flow_current_state, RC_FRAME_WAITING_IN, PC_TRANSMIT_ON_IN, PC_SOD_IN, TC_TRANSMIT_DONE_IN)
begin
  case flow_current_state is

    when IDLE =>
      state <= x"1";
      if (RC_FRAME_WAITING_IN = '1') and (PC_TRANSMIT_ON_IN = '0') then
	flow_next_state <= TRANSMIT_CTRL;
      elsif (PC_SOD_IN = '1') then  -- pottential loss of frames
	flow_next_state <= TRANSMIT_DATA;
      else
	flow_next_state <= IDLE;
      end if;

    when TRANSMIT_DATA =>
      state <= x"2";
      if (TC_TRANSMIT_DONE_IN = '1') then
	flow_next_state <= CLEANUP;
      else
	flow_next_state <= TRANSMIT_DATA;
      end if;

    when TRANSMIT_CTRL =>
      state <= x"3";
      if (TC_TRANSMIT_DONE_IN = '1') then
	flow_next_state <= CLEANUP;
      else
	flow_next_state <= TRANSMIT_CTRL;
      end if;

    when CLEANUP =>
      state <= x"4";
      flow_next_state <= IDLE;

  end case;
end process FLOW_MACHINE;

TC_TRANSMIT_DATA_OUT <= '1' when (flow_current_state = TRANSMIT_DATA) else '0';
TC_TRANSMIT_CTRL_OUT <= '1' when (flow_current_state = TRANSMIT_CTRL) else '0';

RC_LOADING_DONE_OUT  <= '1' when (flow_current_state = TRANSMIT_CTRL) and (TC_TRANSMIT_DONE_IN = '1') else '0';

-- -- hold incoming frame until transmit controller is able to handle it
-- TC_CTRL_FRAME_REQ_OUT <= saved_frame_req_t;
-- 
-- saved_frame_req_t <= '1' when ((RC_FRAME_READY_IN = '1') and (TC_BUSY_IN = '0'))
-- 			or ((saved_frame_req_q = '1') and (TC_BUSY_IN = '0'))
-- 			else '0';
-- 
-- SAVED_FRAME_REQ_PROC : process(CLK)
-- begin
--   if rising_edge(CLK) then
-- 
--     saved_frame_req_q <= saved_frame_req;
-- 
--     if (RESET = '1') or (saved_frame_req_t = '1') then
--       saved_frame_req <= '0';
--     elsif (TC_BUSY_IN = '1') and (RC_FRAME_READY_IN = '1') then
--       saved_frame_req <= '1';
--     end if;
--   end if;
-- end process SAVED_FRAME_REQ_PROC;



--***********************
--	LINK STATE CONTROL

LINK_STATE_MACHINE_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			link_current_state <= INACTIVE;
		else
			link_current_state <= link_next_state;
		end if;
	end if;
end process;

LINK_STATE_MACHINE : process(link_current_state, PCS_AN_COMPLETE_IN, tsm_ready, link_ok_timeout_ctr, PC_READY_IN)
begin
	case link_current_state is

		when ACTIVE =>
			if (PCS_AN_COMPLETE_IN = '0') then
				link_next_state <= INACTIVE; --ENABLE_MAC;
			else
				link_next_state <= ACTIVE;
			end if;

		when INACTIVE =>
			if (PCS_AN_COMPLETE_IN = '1') then
				link_next_state <= TIMEOUT;
			else
				link_next_state <= INACTIVE;
			end if;

		when TIMEOUT =>
			if (PCS_AN_COMPLETE_IN = '0') then
				link_next_state <= INACTIVE;
			else
				if (link_ok_timeout_ctr = x"ffff") then
					link_next_state <= ENABLE_MAC; --FINALIZE;
				else
					link_next_state <= TIMEOUT;
				end if;
			end if;

		when ENABLE_MAC =>
			if (PCS_AN_COMPLETE_IN = '0') then
			  link_next_state <= INACTIVE;
			elsif (tsm_ready = '1') then
			  link_next_state <= FINALIZE; --INACTIVE;
			else
			  link_next_state <= ENABLE_MAC;
			end if;

		when FINALIZE =>
			if (PCS_AN_COMPLETE_IN = '0') then
				link_next_state <= INACTIVE;
			else
				if (PC_READY_IN = '1') then
					link_next_state <= ACTIVE;
				else
					link_next_state <= FINALIZE;
				end if;
			end if;

	end case;
end process LINK_STATE_MACHINE;

LINK_OK_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (link_current_state /= TIMEOUT) then
			link_ok_timeout_ctr <= (others => '0');
		elsif (link_current_state = TIMEOUT) then
			link_ok_timeout_ctr <= link_ok_timeout_ctr + x"1";
		end if;
	end if;
end process LINK_OK_CTR_PROC;

link_ok <= '1' when (link_current_state = ACTIVE) else '0';


LINK_DOWN_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			link_down_ctr      <= (others => '0');
			link_down_ctr_lock <= '0';
		elsif (PCS_AN_COMPLETE_IN = '1') then
			link_down_ctr_lock <= '0';
		elsif ((PCS_AN_COMPLETE_IN = '0') and (link_down_ctr_lock = '0')) then
			link_down_ctr      <= link_down_ctr + x"1";
			link_down_ctr_lock <= '1';
		end if;
	end if;
end process LINK_DOWN_CTR_PROC;

MC_LINK_OK_OUT <= link_ok;

-- END OF LINK STATE CONTROL
--*************


--****************
-- TRI SPEED MAC CONTROLLER

TSMAC_CONTROLLER : trb_net16_gbe_mac_control
port map(
	CLK			=> CLK,
	RESET			=> RESET,

-- signals to/from main controller
	MC_TSMAC_READY_OUT	=> tsm_ready,
	MC_RECONF_IN		=> tsm_reconf,
	MC_GBE_EN_IN		=> '1',
	MC_RX_DISCARD_FCS	=> '0',
	MC_PROMISC_IN		=> '1',
	MC_MAC_ADDR_IN		=> x"001122334455",

-- signal to/from Host interface of TriSpeed MAC
	TSM_HADDR_OUT		=> tsm_haddr,
	TSM_HDATA_OUT		=> tsm_hdata,
	TSM_HCS_N_OUT		=> tsm_hcs_n,
	TSM_HWRITE_N_OUT	=> tsm_hwrite_n,
	TSM_HREAD_N_OUT		=> tsm_hread_n,
	TSM_HREADY_N_IN		=> TSM_HREADY_N_IN,
	TSM_HDATA_EN_N_IN	=> TSM_HDATA_EN_N_IN,

	DEBUG_OUT		=> mac_control_debug
);

--DEBUG_OUT <= mac_control_debug;

tsm_reconf <= '1' when (link_current_state = INACTIVE) and (link_current_state = TIMEOUT) else '0';

TSM_HADDR_OUT     <= tsm_haddr;
TSM_HCS_N_OUT     <= tsm_hcs_n;
TSM_HDATA_OUT     <= tsm_hdata;
TSM_HREAD_N_OUT   <= tsm_hread_n;
TSM_HWRITE_N_OUT  <= tsm_hwrite_n;

-- END OF TRI SPEED MAC CONTROLLER
--***************



end trb_net16_gbe_main_control;


