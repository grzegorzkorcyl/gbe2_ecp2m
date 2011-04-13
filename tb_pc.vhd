LIBRARY ieee;                                                   
USE ieee.std_logic_1164.ALL;                                    
USE ieee.numeric_std.ALL;                                       
                                                                
ENTITY testbench IS                                             
END testbench;                                                  
                                                                
ARCHITECTURE behavior OF testbench IS                           
                                                                
	COMPONENT trb_net16_gbe_packet_constr                       
	PORT(                                                       
		RESET : IN std_logic;                                   
		CLK : IN std_logic;                                     
		PC_WR_EN_IN : IN std_logic;                             
		PC_DATA_IN : IN std_logic_vector(7 downto 0);           
		PC_START_OF_SUB_IN : IN std_logic;                      
		PC_END_OF_DATA_IN : IN std_logic;                       
		PC_SUB_SIZE_IN : IN std_logic_vector(31 downto 0);      
		PC_DECODING_IN : IN std_logic_vector(31 downto 0);      
		PC_EVENT_ID_IN : IN std_logic_vector(31 downto 0);      
		PC_TRIG_NR_IN : IN std_logic_vector(31 downto 0);       
		PC_QUEUE_DEC_IN : IN std_logic_vector(31 downto 0);     
		PC_MAX_FRAME_SIZE_IN : IN std_logic_vector(15 downto 0);
		FC_H_READY_IN : IN std_logic;                           
		FC_READY_IN : IN std_logic;                             
		PC_READY_OUT : OUT std_logic;                           
		FC_WR_EN_OUT : OUT std_logic;                           
		FC_DATA_OUT : OUT std_logic_vector(7 downto 0);         
		FC_IP_SIZE_OUT : OUT std_logic_vector(15 downto 0);     
		FC_UDP_SIZE_OUT : OUT std_logic_vector(15 downto 0);    
		FC_IDENT_OUT : OUT std_logic_vector(15 downto 0);       
		FC_FLAGS_OFFSET_OUT : OUT std_logic_vector(15 downto 0);
		FC_SOD_OUT : OUT std_logic;                             
		FC_EOD_OUT : OUT std_logic;                             
		BSM_CONSTR_OUT : OUT std_logic_vector(3 downto 0);      
		BSM_LOAD_OUT : OUT std_logic_vector(3 downto 0);        
		BSM_SAVE_OUT : OUT std_logic_vector(3 downto 0);        
		DBG_SHF_EMPTY : OUT std_logic;
		DBG_SHF_FULL : OUT std_logic;
		DBG_SHF_WR_EN : OUT std_logic;
		DBG_SHF_RD_EN : OUT std_logic;
		DBG_DF_EMPTY : OUT std_logic;
		DBG_DF_FULL : OUT std_logic;
		DBG_DF_WR_EN : OUT std_logic;
		DBG_DF_RD_EN : OUT std_logic;
		DBG_ALL_CTR : OUT std_logic_vector(4 downto 0);
		DBG_SUB_CTR : OUT std_logic_vector(4 downto 0);
		DBG_MY_CTR : OUT std_logic_vector(1 downto 0);
		DBG_BYTES_LOADED : OUT std_logic_vector(15 downto 0);
		DBG_SIZE_LEFT : OUT std_logic_vector(31 downto 0);
		DBG_SUB_SIZE_TO_SAVE : OUT std_logic_vector(31 downto 0);
		DBG_SUB_SIZE_LOADED : OUT std_logic_vector(31 downto 0);
		DBG_SUB_BYTES_LOADED : OUT std_logic_vector(31 downto 0);
		DBG_QUEUE_SIZE : OUT std_logic_vector(31 downto 0);
		DBG_ACT_QUEUE_SIZE : OUT std_logic_vector(31 downto 0);
		DEBUG_OUT : OUT std_logic_vector(31 downto 0)           
		);                                                      
	END COMPONENT;                                              

	SIGNAL RESET :  std_logic;                                  
	SIGNAL CLK :  std_logic;                                    
	SIGNAL PC_WR_EN_IN :  std_logic;                            
	SIGNAL PC_DATA_IN :  std_logic_vector(7 downto 0);          
	SIGNAL PC_READY_OUT :  std_logic;                           
	SIGNAL PC_START_OF_SUB_IN :  std_logic;                     
	SIGNAL PC_END_OF_DATA_IN :  std_logic;                      
	SIGNAL PC_SUB_SIZE_IN :  std_logic_vector(31 downto 0);     
	SIGNAL PC_DECODING_IN :  std_logic_vector(31 downto 0);     
	SIGNAL PC_EVENT_ID_IN :  std_logic_vector(31 downto 0);     
	SIGNAL PC_TRIG_NR_IN :  std_logic_vector(31 downto 0);      
	SIGNAL PC_QUEUE_DEC_IN :  std_logic_vector(31 downto 0);    
	SIGNAL PC_MAX_FRAME_SIZE_IN :  std_logic_vector(15 downto 0);
	SIGNAL FC_WR_EN_OUT :  std_logic;                           
	SIGNAL FC_DATA_OUT :  std_logic_vector(7 downto 0);         
	SIGNAL FC_H_READY_IN :  std_logic;                          
	SIGNAL FC_READY_IN :  std_logic;                            
	SIGNAL FC_IP_SIZE_OUT :  std_logic_vector(15 downto 0);     
	SIGNAL FC_UDP_SIZE_OUT :  std_logic_vector(15 downto 0);    
	SIGNAL FC_IDENT_OUT :  std_logic_vector(15 downto 0);       
	SIGNAL FC_FLAGS_OFFSET_OUT :  std_logic_vector(15 downto 0);
	SIGNAL FC_SOD_OUT :  std_logic;                             
	SIGNAL FC_EOD_OUT :  std_logic;                             
	SIGNAL BSM_CONSTR_OUT :  std_logic_vector(3 downto 0);      
	SIGNAL BSM_LOAD_OUT :  std_logic_vector(3 downto 0);        
	SIGNAL BSM_SAVE_OUT :  std_logic_vector(3 downto 0);        
	SIGNAL DBG_SHF_EMPTY :  std_logic;
	SIGNAL DBG_SHF_FULL :  std_logic;
	SIGNAL DBG_SHF_WR_EN :  std_logic;
	SIGNAL DBG_SHF_RD_EN :  std_logic;
	SIGNAL DBG_DF_EMPTY :  std_logic;
	SIGNAL DBG_DF_FULL :  std_logic;
	SIGNAL DBG_DF_WR_EN :  std_logic;
	SIGNAL DBG_DF_RD_EN :  std_logic;
	SIGNAL DBG_ALL_CTR :  std_logic_vector(4 downto 0);
	SIGNAL DBG_SUB_CTR :  std_logic_vector(4 downto 0);
	SIGNAL DBG_MY_CTR :  std_logic_vector(1 downto 0);
	SIGNAL DBG_BYTES_LOADED :  std_logic_vector(15 downto 0);
	SIGNAL DBG_SIZE_LEFT :  std_logic_vector(31 downto 0);
	SIGNAL DBG_SUB_SIZE_TO_SAVE :  std_logic_vector(31 downto 0);
	SIGNAL DBG_SUB_SIZE_LOADED :  std_logic_vector(31 downto 0);
	SIGNAL DBG_SUB_BYTES_LOADED :  std_logic_vector(31 downto 0);
	SIGNAL DBG_QUEUE_SIZE :  std_logic_vector(31 downto 0);
	SIGNAL DBG_ACT_QUEUE_SIZE :  std_logic_vector(31 downto 0);
	SIGNAL DEBUG_OUT :  std_logic_vector(31 downto 0);          
                                                                
BEGIN                                                           
                                                                
-- Please check and add your generic clause manually            
	uut: trb_net16_gbe_packet_constr PORT MAP(                  
		RESET => RESET,                                         
		CLK => CLK,                                             
		PC_WR_EN_IN => PC_WR_EN_IN,                             
		PC_DATA_IN => PC_DATA_IN,                               
		PC_READY_OUT => PC_READY_OUT,                           
		PC_START_OF_SUB_IN => PC_START_OF_SUB_IN,               
		PC_END_OF_DATA_IN => PC_END_OF_DATA_IN,                 
		PC_SUB_SIZE_IN => PC_SUB_SIZE_IN,                       
		PC_DECODING_IN => PC_DECODING_IN,                       
		PC_EVENT_ID_IN => PC_EVENT_ID_IN,                       
		PC_TRIG_NR_IN => PC_TRIG_NR_IN,                         
		PC_QUEUE_DEC_IN => PC_QUEUE_DEC_IN,
		PC_MAX_FRAME_SIZE_IN => PC_MAX_FRAME_SIZE_IN,                     
		FC_WR_EN_OUT => FC_WR_EN_OUT,                           
		FC_DATA_OUT => FC_DATA_OUT,                             
		FC_H_READY_IN => FC_H_READY_IN,                         
		FC_READY_IN => FC_READY_IN,                             
		FC_IP_SIZE_OUT => FC_IP_SIZE_OUT,                       
		FC_UDP_SIZE_OUT => FC_UDP_SIZE_OUT,                     
		FC_IDENT_OUT => FC_IDENT_OUT,                           
		FC_FLAGS_OFFSET_OUT => FC_FLAGS_OFFSET_OUT,             
		FC_SOD_OUT => FC_SOD_OUT,                               
		FC_EOD_OUT => FC_EOD_OUT,                               
		BSM_CONSTR_OUT => BSM_CONSTR_OUT,                       
		BSM_LOAD_OUT => BSM_LOAD_OUT,                           
		BSM_SAVE_OUT => BSM_SAVE_OUT,                           
		DBG_SHF_EMPTY => DBG_SHF_EMPTY,
		DBG_SHF_FULL => DBG_SHF_FULL,
		DBG_SHF_WR_EN => DBG_SHF_WR_EN,
		DBG_SHF_RD_EN => DBG_SHF_RD_EN,
		DBG_DF_EMPTY => DBG_DF_EMPTY,
		DBG_DF_FULL => DBG_DF_FULL,
		DBG_DF_WR_EN => DBG_DF_WR_EN,
		DBG_DF_RD_EN => DBG_DF_RD_EN,
		DBG_ALL_CTR => DBG_ALL_CTR,
		DBG_SUB_CTR => DBG_SUB_CTR,
		DBG_MY_CTR => DBG_MY_CTR,
		DBG_BYTES_LOADED => DBG_BYTES_LOADED, 
		DBG_SIZE_LEFT => DBG_SIZE_LEFT, 
		DBG_SUB_SIZE_TO_SAVE => DBG_SUB_SIZE_TO_SAVE,
		DBG_SUB_SIZE_LOADED => DBG_SUB_SIZE_LOADED,
		DBG_SUB_BYTES_LOADED => DBG_SUB_BYTES_LOADED,
		DBG_QUEUE_SIZE => DBG_QUEUE_SIZE,
		DBG_ACT_QUEUE_SIZE => DBG_ACT_QUEUE_SIZE,
		DEBUG_OUT => DEBUG_OUT
	);                                                          
                                                                
CLK_GEN: process
begin
	clk <= '1'; wait for 5.0 ns;
	clk <= '0'; wait for 5.0 ns;
end process CLK_GEN;

THE_TESTBENCH: process
variable test_data_len    : integer range 0 to 65535 := 1;
variable test_loop_len    : integer range 0 to 65535 := 0;
variable test_evt_len     : unsigned(15 downto 0) := x"0000";
variable test_evt_len_vec : std_logic_vector(15 downto 0);
variable test_sub_len     : unsigned(15 downto 0) := x"0000";
variable test_sub_len_vec : std_logic_vector(15 downto 0);
variable test_data        : unsigned(15 downto 0) := x"ffff";
variable test_data_vec    : std_logic_vector(15 downto 0);

variable trigger_counter  : unsigned(15 downto 0) := x"4710";
variable trigger_loop     : integer range 0 to 65535 := 15;
begin
	-- Set up signals
	reset <= '0';
	pc_wr_en_in <= '0';
	pc_data_in <= x"00";
	pc_start_of_sub_in <= '0';
	pc_end_of_data_in <= '0';
	pc_sub_size_in <= x"0000_0000";
	pc_trig_nr_in <= x"0000_0000";
	pc_decoding_in <= x"0002_0001"; -- static
	pc_event_id_in <= x"0000_00ca"; -- static
	pc_queue_dec_in <= x"0003_0062"; -- static
	pc_max_frame_size_in <= x"0578"; -- static
	fc_h_ready_in <= '0';
	fc_ready_in <= '0';
	wait until rising_edge(clk);

	-- Reset the whole stuff
	wait until rising_edge(clk);
	reset <= '1';
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	reset <= '0';
	wait until rising_edge(clk);
	wait for 200 ns;
	wait until rising_edge(clk);
	
	-- Tests may start now

-------------------------------------------------------------------------------
-- Loop the transmissions
-------------------------------------------------------------------------------
	trigger_counter := x"4710";
	trigger_loop    := 0;

	test_data_len   := 14;

	MY_TRIGGER_LOOP: for J in 0 to trigger_loop loop

		-- calculate the needed variables
		test_loop_len := 2*(test_data_len - 1) + 1;
		test_evt_len := to_unsigned( test_data_len, 16 );
		test_evt_len_vec := std_logic_vector(test_evt_len);
		test_sub_len := test_evt_len + 1;
		test_sub_len_vec := std_logic_vector(test_sub_len);

		-- start of subevent marker
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		pc_trig_nr_in <= x"0000" & std_logic_vector(trigger_counter);
		pc_sub_size_in <= b"0000_0000_0000_00" & test_sub_len_vec & b"00";
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		pc_start_of_sub_in <= '1';
		wait until rising_edge(clk);
		pc_start_of_sub_in <= '0';
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		pc_data_in <= test_evt_len_vec(15 downto 8);
		pc_wr_en_in <= '1';
		wait until rising_edge(clk);
		pc_data_in <= test_evt_len_vec(7 downto 0);
		pc_wr_en_in <= '1';
		wait until rising_edge(clk);
		pc_wr_en_in <= '0';
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		pc_data_in <= x"ff"; -- source address high byte
		pc_wr_en_in <= '1';
		wait until rising_edge(clk);
		pc_data_in <= x"22"; -- source address low byte
		pc_wr_en_in <= '1';
		wait until rising_edge(clk);
		pc_wr_en_in <= '0';
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		
		test_data     := x"ffff";
		MY_DATA_LOOP: for J in 0 to test_loop_len loop
			test_data := test_data + 1;
			test_data_vec := std_logic_vector(test_data);
			wait until rising_edge(clk);
			pc_data_in <= test_data_vec(15 downto 8);
			pc_wr_en_in <= '1';
			wait until rising_edge(clk);
			pc_data_in <= test_data_vec(7 downto 0);
			pc_wr_en_in <= '1';
			wait until rising_edge(clk);
			pc_wr_en_in <= '0';
--			wait until rising_edge(clk);
--			wait until rising_edge(clk);			
		end loop MY_DATA_LOOP;

		-- end of subevent marker
--		wait until rising_edge(clk);
		pc_end_of_data_in <= '1';
		wait until rising_edge(clk);
		pc_end_of_data_in <= '0';
		pc_sub_size_in <= x"0000_0000";
		pc_trig_nr_in <= x"0000_0000";
		wait until rising_edge(clk);
		wait until rising_edge(clk);

		trigger_loop    := trigger_loop + 1;
		trigger_counter := trigger_counter + 1;

		wait for 500 ns;
		wait until rising_edge(clk);
	end loop MY_TRIGGER_LOOP;

--	wait for 8 us;
-------------------------------------------------------------------------------
-- end of loop
-------------------------------------------------------------------------------

	wait until rising_edge(clk);
	fc_ready_in <= '1';
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	fc_h_ready_in <= '1';
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	wait until rising_edge(clk);
	
	-- Stay a while... stay forever!!!Muahahah!!!
	wait;

end process THE_TESTBENCH;                                                                
                                                                
END;                                                            