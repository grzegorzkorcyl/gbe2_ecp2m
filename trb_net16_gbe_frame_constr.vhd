LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;
use work.trb_net16_hub_func.all;

entity trb_net16_gbe_frame_constr is
port( 
	-- ports for user logic
	RESET                   : in    std_logic;
	CLK                     : in    std_logic;
	LINK_OK_IN              : in    std_logic;  -- gk 03.08.10
	--
	WR_EN_IN                : in    std_logic;
	DATA_IN                 : in    std_logic_vector(7 downto 0);
	START_OF_DATA_IN        : in    std_logic;
	END_OF_DATA_IN          : in    std_logic;
	IP_F_SIZE_IN            : in    std_logic_vector(15 downto 0);
	UDP_P_SIZE_IN           : in    std_logic_vector(15 downto 0); -- needed for fragmentation
	HEADERS_READY_OUT       : out   std_logic;
	READY_OUT               : out   std_logic;
	DEST_MAC_ADDRESS_IN     : in    std_logic_vector(47 downto 0);
	DEST_IP_ADDRESS_IN      : in    std_logic_vector(31 downto 0);
	DEST_UDP_PORT_IN        : in    std_logic_vector(15 downto 0);
	SRC_MAC_ADDRESS_IN      : in    std_logic_vector(47 downto 0);
	SRC_IP_ADDRESS_IN       : in    std_logic_vector(31 downto 0);
	SRC_UDP_PORT_IN         : in    std_logic_vector(15 downto 0);
	FRAME_TYPE_IN           : in    std_logic_vector(15 downto 0);
	IHL_VERSION_IN          : in    std_logic_vector(7 downto 0);
	TOS_IN                  : in    std_logic_vector(7 downto 0);
	IDENTIFICATION_IN       : in    std_logic_vector(15 downto 0);
	FLAGS_OFFSET_IN         : in    std_logic_vector(15 downto 0);
	TTL_IN                  : in    std_logic_vector(7 downto 0);
	PROTOCOL_IN             : in    std_logic_vector(7 downto 0);
	FRAME_DELAY_IN          : in    std_logic_vector(31 downto 0);  -- gk 09.12.10
	-- ports for packetTransmitter
	RD_CLK                  : in    std_logic; -- 125MHz clock!!!
	FT_DATA_OUT             : out   std_logic_vector(8 downto 0);
	FT_TX_EMPTY_OUT         : out   std_logic;
	FT_TX_RD_EN_IN          : in    std_logic;
	FT_START_OF_PACKET_OUT  : out   std_logic;
	FT_TX_DONE_IN           : in    std_logic;
	FT_TX_DISCFRM_IN	: in	std_logic;
	-- debug ports
	BSM_CONSTR_OUT          : out   std_logic_vector(7 downto 0);
	BSM_TRANS_OUT           : out   std_logic_vector(3 downto 0);
	DEBUG_OUT               : out   std_logic_vector(63 downto 0)
);
end trb_net16_gbe_frame_constr;

architecture trb_net16_gbe_frame_constr of trb_net16_gbe_frame_constr is

attribute HGROUP : string;
attribute HGROUP of trb_net16_gbe_frame_constr : architecture  is "GBE_LINK_group";

component fifo_4096x9 is
port( 
	Data    : in    std_logic_vector(8 downto 0);
	WrClock : in    std_logic;
	RdClock : in    std_logic;
	WrEn    : in    std_logic;
	RdEn    : in    std_logic;
	Reset   : in    std_logic;
	RPReset : in    std_logic;
	Q       : out   std_logic_vector(8 downto 0);
	Empty   : out   std_logic;
	Full    : out   std_logic
);
end component;

attribute sys_encoding      : string;

type constructStates    is  (IDLE, DEST_MAC_ADDR, SRC_MAC_ADDR, FRAME_TYPE_S, VERSION,
							 TOS_S, IP_LENGTH, IDENT, FLAGS, TTL_S, PROTO, HEADER_CS,
							 SRC_IP_ADDR, DEST_IP_ADDR, SRC_PORT, DEST_PORT, UDP_LENGTH,
							 UDP_CS, SAVE_DATA, CLEANUP, DELAY);
signal constructCurrentState, constructNextState : constructStates;
signal bsm_constr           : std_logic_vector(7 downto 0);
attribute sys_encoding of constructCurrentState: signal is "safe,gray";

type transmitStates     is  (T_IDLE, T_LOAD, T_TRANSMIT, T_PAUSE, T_CLEANUP);
signal transmitCurrentState, transmitNextState : transmitStates;
signal bsm_trans            : std_logic_vector(3 downto 0);

signal headers_int_counter  : integer range 0 to 6;
signal fpf_data             : std_logic_vector(7 downto 0);
signal fpf_empty            : std_logic;
signal fpf_full             : std_logic;
signal fpf_wr_en            : std_logic;
signal fpf_rd_en            : std_logic;
signal fpf_q                : std_logic_vector(8 downto 0);
signal ip_size              : std_logic_vector(15 downto 0);
signal ip_checksum          : std_logic_vector(31 downto 0);
signal udp_size             : std_logic_vector(15 downto 0);
signal udp_checksum         : std_logic_vector(15 downto 0);
signal ft_sop               : std_logic;
signal put_udp_headers      : std_logic;
signal ready_frames_ctr     : std_logic_vector(15 downto 0);
signal sent_frames_ctr      : std_logic_vector(15 downto 0);
signal debug                : std_logic_vector(63 downto 0);
signal ready                : std_logic;
signal headers_ready        : std_logic;

signal cur_max : integer range 0 to 10;

signal ready_frames_ctr_q   : std_logic_vector(15 downto 0);
signal ip_cs_temp_right     : std_logic_vector(15 downto 0); -- gk 29.03.10

signal fpf_reset            : std_logic;  -- gk 01.01.01

-- gk 09.12.10
signal delay_ctr            : std_logic_vector(31 downto 0);
signal frame_delay_reg      : std_logic_vector(31 downto 0);

begin

-- Fakes
udp_checksum  <= x"0000";  -- no checksum test needed
--debug         <= (others => '0');

ready         <= '1' when (constructCurrentState = IDLE)
					 else '0';
headers_ready <= '1' when (constructCurrentState = SAVE_DATA)
					 else '0';

sizeProc: process( put_udp_headers, IP_F_SIZE_IN, UDP_P_SIZE_IN, DEST_UDP_PORT_IN)
begin
	if( put_udp_headers = '1' ) and (DEST_UDP_PORT_IN /= x"0000") then
		ip_size  <= IP_F_SIZE_IN + x"14" + x"8";
		udp_size <= UDP_P_SIZE_IN + x"8";
	else
		ip_size  <= IP_F_SIZE_IN + x"14";
		udp_size <= UDP_P_SIZE_IN;
	end if;
end process sizeProc;

ipCsProc : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (constructCurrentState = IDLE) then
			ip_checksum <= x"00000000";
		else
			case constructCurrentState is
				when DEST_MAC_ADDR =>
					case headers_int_counter is
						when 0 =>
							ip_checksum(31 downto 8) <= ip_checksum(31 downto 8) + SRC_IP_ADDRESS_IN(7 downto 0);
						when 1 =>
							ip_checksum <= ip_checksum +  SRC_IP_ADDRESS_IN(15 downto 8);
						when 2 =>
							ip_checksum(31 downto 8) <= ip_checksum(31 downto 8) + SRC_IP_ADDRESS_IN(23 downto 16);
						when 3 =>
							ip_checksum <= ip_checksum +  SRC_IP_ADDRESS_IN(31 downto 24);
						when 4 =>
							ip_checksum(31 downto 8) <= ip_checksum(31 downto 8) + DEST_IP_ADDRESS_IN(7 downto 0);
						when 5 =>
							ip_checksum <= ip_checksum +  DEST_IP_ADDRESS_IN(15 downto 8);
						when others => null;
					end case;
				when SRC_MAC_ADDR =>
					case headers_int_counter is
						when 0 =>
							ip_checksum(31 downto 8) <= ip_checksum(31 downto 8) + DEST_IP_ADDRESS_IN(23 downto 16);
						when 1 =>
							ip_checksum <= ip_checksum +  DEST_IP_ADDRESS_IN(31 downto 24);
						when 2 =>
							ip_checksum(31 downto 8) <= ip_checksum(31 downto 8) + IHL_VERSION_IN;
						when 3 =>
							ip_checksum <= ip_checksum + TOS_IN;
						when 4 =>
							ip_checksum(31 downto 8) <= ip_checksum(31 downto 8) + ip_size(15 downto 8);
						when 5 =>
							ip_checksum <= ip_checksum + ip_size(7 downto 0);
						when others => null;
					end case;
				when VERSION =>
					if headers_int_counter = 0 then
						ip_checksum(31 downto 8) <= ip_checksum(31 downto 8) + IDENTIFICATION_IN(7 downto 0);
					end if;
				when TOS_S =>
					if headers_int_counter = 0 then
						ip_checksum <= ip_checksum + IDENTIFICATION_IN(15 downto 8);
					end if;
				when IP_LENGTH =>
					if headers_int_counter = 0 then
						ip_checksum(31 downto 8) <= ip_checksum(31 downto 8) + FLAGS_OFFSET_IN(15 downto 8);
					elsif headers_int_counter = 1 then
						ip_checksum <= ip_checksum + FLAGS_OFFSET_IN(7 downto 0);
					end if;
				when IDENT =>
					if headers_int_counter = 0 then
						ip_checksum(31 downto 8) <= ip_checksum(31 downto 8) + TTL_IN;
					elsif headers_int_counter = 1 then
						ip_checksum <= ip_checksum + PROTOCOL_IN;
					end if;
				-- gk 29.03.10 corrected the bug with bad checksums when sum larger than 16b
				when FLAGS =>
					if headers_int_counter = 0 then
						ip_cs_temp_right <= ip_checksum(31 downto 16);
					elsif headers_int_counter = 1 then
						ip_checksum(31 downto 16) <= (others => '0');
					end if;
				when TTL_S =>
					if headers_int_counter = 0 then
						ip_checksum <= ip_checksum + ip_cs_temp_right;
					end if;
				when PROTO =>
					if headers_int_counter = 0 then
						ip_checksum(15 downto 0) <= ip_checksum(15 downto 0) + ip_checksum(31 downto 16);
					end if;
				when others => null;
			end case;
		end if;
	end if;
end process ipCsProc;


constructMachineProc: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if( RESET = '1' ) then
			constructCurrentState <= IDLE;
		else
			constructCurrentState <= constructNextState;
		end if;
	end if;
end process constructMachineProc;

--find next state of construct machine
constructMachine: process( constructCurrentState, delay_ctr, FRAME_DELAY_IN, START_OF_DATA_IN, END_OF_DATA_IN, headers_int_counter, put_udp_headers, CUR_MAX, FRAME_TYPE_IN, DEST_IP_ADDRESS_IN, DEST_UDP_PORT_IN)
begin
	constructNextState <= constructCurrentState;
	if( headers_int_counter = cur_max ) then    --can be checked everytime - if not in use, counter and cur_max are 0
		case constructCurrentState is
			when IDLE =>
				if( START_OF_DATA_IN = '1' ) then
					constructNextState <= DEST_MAC_ADDR;
				end if;
			when DEST_MAC_ADDR =>
				constructNextState <= SRC_MAC_ADDR;
			when SRC_MAC_ADDR =>
				constructNextState <= FRAME_TYPE_S;
			when FRAME_TYPE_S =>
				if (DEST_IP_ADDRESS_IN /= x"0000_0000") then -- in case of ip frame continue with ip/udp headers 
					constructNextState <= VERSION;
				else  -- otherwise transmit data as pure ethernet frame
					constructNextState <= SAVE_DATA;
				end if;
			when VERSION =>
				constructNextState <= TOS_S;
			when TOS_S =>
				constructNextState <= IP_LENGTH;
			when IP_LENGTH =>
				constructNextState <= IDENT;
			when IDENT =>
				constructNextState <= FLAGS;
			when FLAGS =>
				constructNextState <= TTL_S;
			when TTL_S =>
				constructNextState <= PROTO;
			when PROTO =>
				constructNextState <= HEADER_CS;
			when HEADER_CS =>
				constructNextState <= SRC_IP_ADDR;
			when SRC_IP_ADDR =>
				constructNextState <= DEST_IP_ADDR;
			when DEST_IP_ADDR =>
				if (put_udp_headers = '1') and (DEST_UDP_PORT_IN /= x"0000") then
					constructNextState <= SRC_PORT;
				else
					constructNextState <= SAVE_DATA;
				end if;
			when SRC_PORT =>
				constructNextState <= DEST_PORT;
			when DEST_PORT =>
				constructNextState <= UDP_LENGTH;
			when UDP_LENGTH =>
				constructNextState <= UDP_CS;
			when UDP_CS =>
				constructNextState <= SAVE_DATA;
			when SAVE_DATA =>
				if (END_OF_DATA_IN = '1') then
					constructNextState <= CLEANUP;
				end if;
			when CLEANUP =>
				--constructNextState <= IDLE;
				constructNextState <= DELAY; -- gk 10.12.10 IDLE;
			-- gk 09.12.10
			when DELAY =>
				if (delay_ctr = FRAME_DELAY_IN) then
					constructNextState <= IDLE;
				else
					constructNextState <= DELAY;
				end if;

			when others =>
				constructNextState <= IDLE;
		end case;
	end if;
end process constructMachine;

-- gk 09.12.10
delayCtrProc : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (constructCurrentState = IDLE) or (constructCurrentState = CLEANUP) then
			delay_ctr <= (others => '0');
		elsif (constructCurrentState = DELAY) then
			delay_ctr <= delay_ctr + x"1";
		end if;

		frame_delay_reg <= FRAME_DELAY_IN;
	end if;
end process delayCtrProc;


bsmConstrProc : process(constructCurrentState)
begin
--find maximum time in each state & set state bits
	case constructCurrentState is
		when IDLE =>            cur_max    <= 0;     bsm_constr <= x"01";
		when DEST_MAC_ADDR =>   cur_max    <= 5;     bsm_constr <= x"02";
		when SRC_MAC_ADDR =>    cur_max    <= 5;     bsm_constr <= x"03";
		when FRAME_TYPE_S =>    cur_max    <= 1;     bsm_constr <= x"04";
		when VERSION =>         cur_max    <= 0;     bsm_constr <= x"05";
		when TOS_S =>           cur_max    <= 0;     bsm_constr <= x"06";
		when IP_LENGTH =>       cur_max    <= 1;     bsm_constr <= x"07";
		when IDENT =>           cur_max    <= 1;     bsm_constr <= x"08";
		when FLAGS =>           cur_max    <= 1;     bsm_constr <= x"09";
		when TTL_S =>           cur_max    <= 0;     bsm_constr <= x"0a";
		when PROTO =>           cur_max    <= 0;     bsm_constr <= x"0b";
		when HEADER_CS =>       cur_max    <= 1;     bsm_constr <= x"0c";
		when SRC_IP_ADDR =>     cur_max    <= 3;     bsm_constr <= x"0d";
		when DEST_IP_ADDR =>    cur_max    <= 3;     bsm_constr <= x"0e";
		when SRC_PORT =>        cur_max    <= 1;     bsm_constr <= x"0f";
		when DEST_PORT =>       cur_max    <= 1;     bsm_constr <= x"10";
		when UDP_LENGTH =>      cur_max    <= 1;     bsm_constr <= x"11";
		when UDP_CS =>          cur_max    <= 1;     bsm_constr <= x"12";
		when SAVE_DATA =>       cur_max    <= 0;     bsm_constr <= x"13";
		when CLEANUP =>         cur_max    <= 0;     bsm_constr <= x"14";
		when DELAY =>           cur_max    <= 0;     bsm_constr <= x"15";
		when others =>          cur_max    <= 0;     bsm_constr <= x"1f";
	end case;
end process;


headersIntProc : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (constructCurrentState = IDLE) then
			headers_int_counter <= 0;
		else
			if (headers_int_counter = cur_max) then
				headers_int_counter <= 0;
			else
				headers_int_counter <= headers_int_counter + 1;
			end if;
		end if;
	end if;
end process headersIntProc;



putUdpHeadersProc : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (FLAGS_OFFSET_IN(12 downto 0) = "0000000000000") then
			put_udp_headers <= '1';
		else
			put_udp_headers <= '0';
		end if;
	end if;
end process putUdpHeadersProc;


fpfWrEnProc : process(constructCurrentState, WR_EN_IN, RESET, LINK_OK_IN)
begin
	if (RESET = '1') or (LINK_OK_IN = '0') then  -- gk 01.10.10
		fpf_wr_en <= '0';
	elsif (constructCurrentState /= IDLE) and (constructCurrentState /= CLEANUP) and (constructCurrentState /= SAVE_DATA)  and (constructCurrentState /= DELAY) then
		fpf_wr_en <= '1';
	elsif (constructCurrentState = SAVE_DATA) and (WR_EN_IN = '1') then
		fpf_wr_en <= '1';
	else
		fpf_wr_en <= '0';
	end if;
end process fpfWrEnProc;

fpfDataProc : process(constructCurrentState, DEST_MAC_ADDRESS_IN, SRC_MAC_ADDRESS_IN, FRAME_TYPE_IN, IHL_VERSION_IN,
					  TOS_IN, ip_size, IDENTIFICATION_IN, FLAGS_OFFSET_IN, TTL_IN, PROTOCOL_IN,
					  ip_checksum, SRC_IP_ADDRESS_IN, DEST_IP_ADDRESS_IN,
					  SRC_UDP_PORT_IN, DEST_UDP_PORT_IN, udp_size, udp_checksum, headers_int_counter, DATA_IN)
begin
	case constructCurrentState is
		when IDLE           =>  fpf_data <= DEST_MAC_ADDRESS_IN(headers_int_counter * 8 + 7 downto headers_int_counter * 8);
		when DEST_MAC_ADDR  =>  fpf_data <= DEST_MAC_ADDRESS_IN(headers_int_counter * 8 + 7 downto headers_int_counter * 8);
		when SRC_MAC_ADDR   =>  fpf_data <= SRC_MAC_ADDRESS_IN(headers_int_counter * 8 + 7 downto headers_int_counter * 8);
		when FRAME_TYPE_S   =>  fpf_data <= FRAME_TYPE_IN(headers_int_counter * 8 + 7 downto headers_int_counter * 8);
		when VERSION        =>  fpf_data <= IHL_VERSION_IN;
		when TOS_S          =>  fpf_data <= TOS_IN;
		when IP_LENGTH      =>  fpf_data <= ip_size(15 - headers_int_counter * 8 downto 8 - headers_int_counter * 8);
		when IDENT          =>  fpf_data <= IDENTIFICATION_IN(headers_int_counter * 8 + 7 downto headers_int_counter * 8);
		when FLAGS          =>  fpf_data <= FLAGS_OFFSET_IN(15 - headers_int_counter * 8 downto 8 - headers_int_counter * 8);
		when TTL_S          =>  fpf_data <= TTL_IN;
		when PROTO          =>  fpf_data <= PROTOCOL_IN;
		when HEADER_CS      =>  fpf_data <= x"ff" - ip_checksum(15 - headers_int_counter * 8 downto 8 - headers_int_counter * 8);
		when SRC_IP_ADDR    =>  fpf_data <= SRC_IP_ADDRESS_IN(headers_int_counter * 8 + 7 downto headers_int_counter * 8);
		when DEST_IP_ADDR   =>  fpf_data <= DEST_IP_ADDRESS_IN(headers_int_counter * 8 + 7 downto headers_int_counter * 8);
		when SRC_PORT       =>  fpf_data <= SRC_UDP_PORT_IN(headers_int_counter * 8 + 7 downto headers_int_counter * 8);
		when DEST_PORT      =>  fpf_data <= DEST_UDP_PORT_IN(headers_int_counter * 8 + 7 downto headers_int_counter * 8);
		when UDP_LENGTH     =>  fpf_data <= udp_size(15 - headers_int_counter * 8 downto 8 - headers_int_counter * 8);
		when UDP_CS         =>  fpf_data <= udp_checksum(15 - headers_int_counter * 8 downto 8 - headers_int_counter * 8);
		when SAVE_DATA      =>  fpf_data <= DATA_IN;
		when CLEANUP        =>  fpf_data <= x"ab";
		when DELAY          =>  fpf_data <= x"ac";
		when others         =>  fpf_data <= x"00";
	end case;
end process fpfDataProc;


readyFramesCtrProc: process( CLK )
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (LINK_OK_IN = '0') then  -- gk 01.10.10
			ready_frames_ctr <= (others => '0');
		elsif (constructCurrentState = CLEANUP) then
			ready_frames_ctr <= ready_frames_ctr + 1;
		end if;
	end if;
end process readyFramesCtrProc;

fpf_reset <= '1' when (RESET = '1') or (LINK_OK_IN = '0') else '0';  -- gk 01.10.10

FINAL_PACKET_FIFO: fifo_4096x9
port map( 
	Data(7 downto 0)    => fpf_data,
	Data(8)             => END_OF_DATA_IN,
	WrClock             => CLK,
	RdClock             => RD_CLK,
	WrEn                => fpf_wr_en,
	RdEn                => fpf_rd_en, --FT_TX_RD_EN_IN,
	Reset               => fpf_reset,
	RPReset             => fpf_reset,
	Q                   => fpf_q,
	Empty               => fpf_empty,
	Full                => fpf_full
);

fpf_rd_en <= '1' when ((LINK_OK_IN = '1') and (FT_TX_RD_EN_IN = '1'))
		    or (LINK_OK_IN = '0')  -- clear the fifo if link is down
		    else '0';

transferToRdClock : signal_sync
	generic map(
	  DEPTH => 2,
	  WIDTH => 16
	  )
	port map(
	  RESET    => RESET,
	  D_IN     => ready_frames_ctr,
	  CLK0     => RD_CLK, --CLK,
	  CLK1     => RD_CLK,
	  D_OUT    => ready_frames_ctr_q
	  );

transmitMachineProc: process( RD_CLK )
begin
	if( rising_edge(RD_CLK) ) then
		if( RESET = '1' ) or (LINK_OK_IN = '0') then  -- gk 01.10.10
			transmitCurrentState <= T_IDLE;
		else
			transmitCurrentState <= transmitNextState;
		end if;
	end if;
end process transmitMachineProc;

transmitMachine: process( transmitCurrentState, fpf_q, FT_TX_DONE_IN, sent_frames_ctr, ready_frames_ctr_q, FT_TX_DISCFRM_IN )
begin
	case transmitCurrentState is
		when T_IDLE =>
			bsm_trans <= x"0";
			if( (sent_frames_ctr /= ready_frames_ctr_q) ) then
				transmitNextState <= T_LOAD;
			else
				transmitNextState <= T_IDLE;
			end if;
		when T_LOAD =>
			bsm_trans <= x"1";
			if( fpf_q(8) = '1' ) then
				transmitNextState <= T_TRANSMIT;
			else
				transmitNextState <= T_LOAD;
			end if;
		when T_TRANSMIT =>
			bsm_trans <= x"2";
			-- gk 03.08.10
			if ((LINK_OK_IN = '1') and ((FT_TX_DONE_IN = '1') or (FT_TX_DISCFRM_IN = '1')))then
				transmitNextState <= T_CLEANUP;
			elsif (LINK_OK_IN = '0') then
				transmitNextState <= T_PAUSE;
			else
				transmitNextState <= T_TRANSMIT;
			end if;
		when T_PAUSE =>
			transmitNextState <= T_CLEANUP;
		when T_CLEANUP =>
			bsm_trans <= x"3";
			transmitNextState <= T_IDLE;
		when others =>
			bsm_trans <= x"f";
			transmitNextState <= T_IDLE;
	end case;
end process transmitMachine;



sopProc: process( RD_CLK )
begin
	if rising_edge(RD_CLK) then
		if   ( RESET = '1' ) or (LINK_OK_IN = '0') then  -- gk 01.10.10
			ft_sop <= '0';
		elsif ((transmitCurrentState = T_IDLE) and (sent_frames_ctr /= ready_frames_ctr_q)) then
			ft_sop <= '1';
		else
			ft_sop <= '0';
		end if;
	end if;
end process sopProc;

sentFramesCtrProc: process( RD_CLK )
begin
	if rising_edge(RD_CLK) then
		if   ( RESET = '1' ) or (LINK_OK_IN = '0') then  -- gk 01.10.10
			sent_frames_ctr <= (others => '0');
		-- gk 03.08.10
		elsif( FT_TX_DONE_IN = '1' ) or (FT_TX_DISCFRM_IN = '1') then
			sent_frames_ctr <= sent_frames_ctr + 1;
		end if;
	end if;
end process sentFramesCtrProc;

debug(7 downto 0)      <= bsm_constr;
debug(11 downto 8)     <= bsm_trans;
debug(27 downto 12)    <= sent_frames_ctr;
debug(28)              <= fpf_full;
debug(29)              <= fpf_empty;
debug(30)              <= ready;
debug(31)              <= headers_ready;
debug(47 downto 32)    <= ready_frames_ctr_q;
debug(48)              <= '0';


-- Output
FT_DATA_OUT            <= fpf_q;
FT_TX_EMPTY_OUT        <= fpf_empty;
FT_START_OF_PACKET_OUT <= ft_sop;
READY_OUT              <= ready;
HEADERS_READY_OUT      <= headers_ready;

BSM_CONSTR_OUT         <= bsm_constr;
BSM_TRANS_OUT          <= bsm_trans;
DEBUG_OUT              <= debug;

end trb_net16_gbe_frame_constr;