LIBRARY ieee;
use ieee.std_logic_1164.all;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;
use work.trb_net16_hub_func.all;
--use work.version.all;


entity gbe_setup is
port(
	CLK                       : in std_logic;
	RESET                     : in std_logic;

	-- interface to regio bus
	BUS_ADDR_IN               : in std_logic_vector(7 downto 0);
	BUS_DATA_IN               : in std_logic_vector(31 downto 0);
	BUS_DATA_OUT              : out std_logic_vector(31 downto 0);  -- gk 26.04.10
	BUS_WRITE_EN_IN           : in std_logic;  -- gk 26.04.10
	BUS_READ_EN_IN            : in std_logic;  -- gk 26.04.10
	BUS_ACK_OUT               : out std_logic;  -- gk 26.04.10

	-- gk 26.04.10
	-- input from gbe_buf (only to return the whole trigger number via regio)
	GBE_TRIG_NR_IN            : in std_logic_vector(31 downto 0);

	-- output to gbe_buf
	GBE_SUBEVENT_ID_OUT       : out std_logic_vector(31 downto 0);
	GBE_SUBEVENT_DEC_OUT      : out std_logic_vector(31 downto 0);
	GBE_QUEUE_DEC_OUT         : out std_logic_vector(31 downto 0);
	GBE_MAX_PACKET_OUT        : out std_logic_vector(31 downto 0);
	GBE_MIN_PACKET_OUT        : out std_logic_vector(31 downto 0);
	GBE_MAX_FRAME_OUT         : out std_logic_vector(15 downto 0);
	GBE_USE_GBE_OUT           : out std_logic;
	GBE_USE_TRBNET_OUT        : out std_logic;
	GBE_USE_MULTIEVENTS_OUT   : out std_logic;
	GBE_READOUT_CTR_OUT       : out std_logic_vector(23 downto 0);  -- gk 26.04.10
	GBE_READOUT_CTR_VALID_OUT : out std_logic;  -- gk 26.04.10
	GBE_DELAY_OUT             : out std_logic_vector(31 downto 0);
	GBE_ALLOW_LARGE_OUT       : out std_logic;
	GBE_ALLOW_RX_OUT          : out std_logic;
	-- gk 28.07.10
	MONITOR_BYTES_IN          : in std_logic_vector(31 downto 0);
	MONITOR_SENT_IN           : in std_logic_vector(31 downto 0);
	MONITOR_DROPPED_IN        : in std_logic_vector(31 downto 0);
	MONITOR_SM_IN             : in std_logic_vector(31 downto 0);
	MONITOR_LR_IN             : in std_logic_vector(31 downto 0);
	MONITOR_HDR_IN            : in std_logic_vector(31 downto 0);
	MONITOR_FIFOS_IN          : in std_logic_vector(31 downto 0);
	MONITOR_DISCFRM_IN        : in std_logic_vector(31 downto 0);
	MONITOR_LINK_DWN_IN       : in std_logic_vector(31 downto 0);  -- gk 30.09.10
	MONITOR_EMPTY_IN          : in std_logic_vector(31 downto 0);  -- gk 01.10.10
	MONITOR_RX_FRAMES_IN      : in std_logic_vector(31 downto 0);
	MONITOR_RX_BYTES_IN       : in std_logic_vector(31 downto 0);
	MONITOR_RX_BYTES_R_IN     : in std_logic_vector(31 downto 0);
	-- gk 01.06.10
	DBG_IPU2GBE1_IN          : in std_logic_vector(31 downto 0);
	DBG_IPU2GBE2_IN          : in std_logic_vector(31 downto 0);
	DBG_IPU2GBE3_IN          : in std_logic_vector(31 downto 0);
	DBG_IPU2GBE4_IN          : in std_logic_vector(31 downto 0);
	DBG_IPU2GBE5_IN          : in std_logic_vector(31 downto 0);
	DBG_IPU2GBE6_IN          : in std_logic_vector(31 downto 0);
	DBG_IPU2GBE7_IN          : in std_logic_vector(31 downto 0);
	DBG_IPU2GBE8_IN          : in std_logic_vector(31 downto 0);
	DBG_IPU2GBE9_IN          : in std_logic_vector(31 downto 0);
	DBG_IPU2GBE10_IN         : in std_logic_vector(31 downto 0);
	DBG_IPU2GBE11_IN         : in std_logic_vector(31 downto 0);
	DBG_IPU2GBE12_IN         : in std_logic_vector(31 downto 0);
	DBG_PC1_IN               : in std_logic_vector(31 downto 0);
	DBG_PC2_IN               : in std_logic_vector(31 downto 0);
	DBG_FC1_IN               : in std_logic_vector(31 downto 0);
	DBG_FC2_IN               : in std_logic_vector(31 downto 0);
	DBG_FT1_IN               : in std_logic_vector(31 downto 0);
	DBG_FT2_IN               : in std_logic_vector(31 downto 0);
	DBG_FR_IN                : in std_logic_vector(31 downto 0);
	DBG_RC_IN                : in std_logic_vector(31 downto 0);
	DBG_MC_IN                : in std_logic_vector(31 downto 0);
	DBG_TC_IN                : in std_logic_vector(31 downto 0);
	DBG_FIFO_RD_EN_OUT        : out std_logic;
	DBG_FIFO_Q_IN             : in std_logic_vector(15 downto 0)
	--DBG_RESET_FIFO_OUT       : out std_logic  -- gk 28.09.10
);
end entity;

architecture gbe_setup of gbe_setup is

-- attribute HGROUP : string;
-- attribute HGROUP of gbe_setup : architecture  is "GBE_conf";

signal reset_values      : std_logic;

signal subevent_id       : std_logic_vector(31 downto 0);
signal subevent_dec      : std_logic_vector(31 downto 0);
signal queue_dec         : std_logic_vector(31 downto 0);
signal max_packet        : std_logic_vector(31 downto 0);
signal min_packet        : std_logic_vector(31 downto 0);  -- gk 07.20.10
signal max_frame         : std_logic_vector(15 downto 0);
signal use_gbe           : std_logic;
signal use_trbnet        : std_logic;
signal use_multievents   : std_logic;
signal readout_ctr       : std_logic_vector(23 downto 0);  -- gk 26.04.10
signal readout_ctr_valid : std_logic;  -- gk 26.04.10
signal ack               : std_logic;  -- gk 26.04.10
signal ack_q             : std_logic;  -- gk 26.04.10
signal data_out          : std_logic_vector(31 downto 0);  -- gk 26.04.10
signal delay             : std_logic_vector(31 downto 0);  -- gk 28.04.10
signal allow_large       : std_logic;  -- gk 21.07.10
signal reset_fifo        : std_logic;  -- gk 28.09.10
signal allow_rx          : std_logic;

begin

OUT_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		GBE_SUBEVENT_ID_OUT       <= subevent_id;
		GBE_SUBEVENT_DEC_OUT      <= subevent_dec;
		GBE_QUEUE_DEC_OUT         <= queue_dec;
		GBE_MAX_PACKET_OUT        <= max_packet;
		GBE_MIN_PACKET_OUT        <= min_packet;
		GBE_MAX_FRAME_OUT         <= max_frame;
		GBE_USE_GBE_OUT           <= use_gbe;
		GBE_USE_TRBNET_OUT        <= use_trbnet;
		GBE_USE_MULTIEVENTS_OUT   <= use_multievents;
		GBE_READOUT_CTR_OUT       <= readout_ctr;  -- gk 26.04.10
		GBE_READOUT_CTR_VALID_OUT <= readout_ctr_valid;  -- gk 26.04.10
		BUS_ACK_OUT               <= ack_q;  -- gk 26.04.10
		ack_q                     <= ack; -- gk 26.04.10
		BUS_DATA_OUT              <= data_out;  -- gk 26.04.10
		GBE_DELAY_OUT             <= delay; -- gk 28.04.10
		GBE_ALLOW_LARGE_OUT       <= allow_large;  -- gk 21.07.10
		GBE_ALLOW_RX_OUT          <= allow_rx;
		--DBG_RESET_FIFO_OUT        <= reset_fifo;  -- gk 28.09.10
	end if;
end process OUT_PROC;

-- gk 26.04.10
ACK_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			ack <= '0';
		elsif ((BUS_WRITE_EN_IN = '1') or (BUS_READ_EN_IN = '1')) then
			ack <= '1';
		else
			ack <= '0';
		end if;
	end if;
end process ACK_PROC;

WRITE_PROC : process(CLK)
begin
	DBG_FIFO_RD_EN_OUT <= '0';

	if rising_edge(CLK) then
		if ( (RESET = '1') or (reset_values = '1') ) then
			subevent_id       <= x"0000_00cf";
			subevent_dec      <= x"0002_0001";
			queue_dec         <= x"0003_0062";
			max_packet        <= x"0000_0fd0"; --x"0000_fde8"; -- 65k --x"0000_fde8"; -- tester
			min_packet        <= x"0000_0007"; -- gk 20.07.10
			max_frame         <= x"0578";
			use_gbe           <= '1'; --'1';  -- gk 27.08.10  -- blocks the transmission until gbe gets configured
			use_trbnet        <= '0';
			use_multievents   <= '0';
			reset_values      <= '0';
			readout_ctr       <= x"00_0000";  -- gk 26.04.10  -- gk 07.06.10 corrected bug found by Sergey
			readout_ctr_valid <= '0';  -- gk 26.04.10
			delay             <= x"0000_0000"; -- gk 28.04.10
			DBG_FIFO_RD_EN_OUT <= '0';
			allow_large       <= '0';  -- gk 21.07.10
			reset_fifo        <= '0';  -- gk 28.09.10
			allow_rx          <= '0';

		elsif (BUS_WRITE_EN_IN = '1') then
			case BUS_ADDR_IN is

				when x"00" =>
					subevent_id <= BUS_DATA_IN;

				when x"01" =>
					subevent_dec <= BUS_DATA_IN;

				when x"02" =>
					queue_dec <= BUS_DATA_IN;

				when x"03" =>
					max_packet <= BUS_DATA_IN;

				when x"04" =>
					max_frame <= BUS_DATA_IN(15 downto 0);

				when x"05" =>
					if (BUS_DATA_IN = x"0000_0000") then
						use_gbe <= '0';
					else
						use_gbe <= '1';
					end if;

				when x"06" =>
					if (BUS_DATA_IN = x"0000_0000") then
						use_trbnet <= '0';
					else
						use_trbnet <= '1';
					end if;

				when x"07" =>
					if (BUS_DATA_IN = x"0000_0000") then
						use_multievents <= '0';
					else
						use_multievents <= '1';
					end if;

  				-- gk 26.04.10
				when x"08" =>
					readout_ctr <= BUS_DATA_IN(23 downto 0);
					readout_ctr_valid <= '1';

				-- gk 28.04.10
				when x"09" =>
					delay <= BUS_DATA_IN;

				when x"0a" =>
					DBG_FIFO_RD_EN_OUT <= '1';

				-- gk 20.07.10
				when x"0b" =>
					min_packet <= BUS_DATA_IN;

				-- gk 21.07.10
				when x"0c" =>
					if (BUS_DATA_IN = x"0000_0000") then
						allow_large <= '0';
					else
						allow_large <= '1';
					end if;

				when x"0d" =>
					if (BUS_DATA_IN = x"0000_0000") then
						allow_rx <= '0';
					else
						allow_rx <= '1';
					end if;

				-- gk 28.09.10
				when x"fe" =>
					if (BUS_DATA_IN = x"ffff_ffff") then
						reset_fifo <= '1';
					else
						reset_fifo <= '0';
					end if;

				when x"ff" =>
					if (BUS_DATA_IN = x"ffff_ffff") then
						reset_values <= '1';
					else
						reset_values <= '0';
					end if;

				when others =>
					subevent_id        <= subevent_id;
					subevent_dec       <= subevent_dec;
					queue_dec          <= queue_dec;
					max_packet         <= max_packet;
					min_packet         <= min_packet;
					max_frame          <= max_frame;
					use_gbe            <= use_gbe;
					use_trbnet         <= use_trbnet;
					use_multievents    <= use_multievents;
					reset_values       <= reset_values;
					readout_ctr        <= readout_ctr;  -- gk 26.04.10
					readout_ctr_valid  <= readout_ctr_valid;  -- gk 26.04.10
					delay              <= delay; -- gk 28.04.10
					DBG_FIFO_RD_EN_OUT <= '0';
					allow_large        <= allow_large;
					reset_fifo         <= reset_fifo; -- gk 28.09.10
					allow_rx           <= allow_rx;
			end case;
		else
			reset_values      <= '0';
			readout_ctr_valid <= '0';  -- gk 26.04.10
			--reset_fifo        <= '0';  -- gk 28.09.10
		end if;
	end if;
end process WRITE_PROC;

-- gk 26.04.10
READ_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			data_out <= (others => '0');
		elsif (BUS_READ_EN_IN = '1') then
			case BUS_ADDR_IN is

				when x"00" =>
					data_out <= subevent_id;

				when x"01" =>
					data_out <= subevent_dec;

				when x"02" =>
					data_out <= queue_dec;

				when x"03" =>
					data_out <= max_packet;

				when x"04" =>
					data_out(15 downto 0) <= max_frame;
					data_out(31 downto 16) <= (others => '0');

				when x"05" =>
					if (use_gbe = '0') then
						data_out <= x"0000_0000";
					else
						data_out <= x"0000_0001";
					end if;

				when x"06" =>
					if (use_trbnet = '0') then
						data_out <= x"0000_0000";
					else
						data_out <= x"0000_0001";
					end if;

				when x"07" =>
					if (use_multievents = '0') then
						data_out <= x"0000_0000";
					else
						data_out <= x"0000_0001";
					end if;

				when x"08" =>
					data_out <= GBE_TRIG_NR_IN;

				when x"09" =>
					data_out <= delay;

				when x"0b" =>
					data_out <= min_packet;

				-- gk 21.07.10
				when x"0c" =>
					if (allow_large = '0') then
						data_out <= x"0000_0000";
					else
						data_out <= x"0000_0001";
					end if;

				when x"0d" =>
					if (allow_rx = '0') then
						data_out <= x"0000_0000";
					else
						data_out <= x"0000_0001";
					end if;

				-- gk 01.06.10
				when x"e0" =>
					data_out <= DBG_IPU2GBE1_IN;

				when x"e1" =>
					data_out <= DBG_IPU2GBE2_IN;

				when x"e2" =>
					data_out <= DBG_PC1_IN;

				when x"e3" =>
					data_out <= DBG_PC2_IN;

				when x"e4" =>
					data_out <= DBG_FC1_IN;

				when x"e5" =>
					data_out <= DBG_FC2_IN;

				when x"e6" =>
					data_out <= DBG_FT1_IN;

				when x"e7" =>
					data_out <= DBG_FT2_IN;

				when x"e8" =>
					data_out(15 downto 0) <= DBG_FIFO_Q_IN;
					data_out(31 downto 16) <= (others => '0');

				when x"e9" =>
					data_out <= DBG_IPU2GBE3_IN;

				when x"ea" =>
					data_out <= DBG_IPU2GBE4_IN;

				when x"eb" =>
					data_out <= DBG_IPU2GBE5_IN;

				when x"ec" =>
					data_out <= DBG_IPU2GBE6_IN;

				when x"ed" =>
					data_out <= DBG_IPU2GBE7_IN;

				when x"ee" =>
					data_out <= DBG_IPU2GBE8_IN;

				when x"ef" =>
					data_out <= DBG_IPU2GBE9_IN;

				when x"f0" =>
					data_out <= DBG_IPU2GBE10_IN;

				when x"f1" =>
					data_out <= DBG_IPU2GBE11_IN;

				when x"f2" =>
					data_out <= DBG_IPU2GBE12_IN;

				when x"f3" =>
					data_out <= MONITOR_BYTES_IN;

				when x"f4" =>
					data_out <= MONITOR_SENT_IN;

				when x"f5" =>
					data_out <= MONITOR_DROPPED_IN;

				when x"f6" =>
					data_out <= MONITOR_SM_IN;

				when x"f7" =>
					data_out <= MONITOR_LR_IN;

				when x"f8" =>
					data_out <= MONITOR_HDR_IN;

				when x"f9" =>
					data_out <= MONITOR_FIFOS_IN;

				when x"fa" =>
					data_out <= MONITOR_DISCFRM_IN;

				when x"fb" =>
					data_out <= MONITOR_LINK_DWN_IN;

				when x"fc" =>
					data_out <= MONITOR_EMPTY_IN;

				when x"fd" =>
					data_out <= MONITOR_RX_FRAMES_IN;

				when x"fe" =>
					data_out <= MONITOR_RX_BYTES_IN;

				when x"d0" =>
					data_out <= MONITOR_RX_BYTES_R_IN;

				when x"d1" =>
					data_out <= DBG_FR_IN;

				when x"d2" =>
					data_out <= DBG_RC_IN;

				when x"d3" =>
					data_out <= DBG_MC_IN;

				when x"d4" =>
					data_out <= DBG_TC_IN;

				when others =>
					data_out <= (others => '0');
			end case;
		end if;
	end if;
end process READ_PROC;

end architecture;