	component jpeg_accelerator is
		port (
			clk_clk : in std_logic := 'X'  -- clk
		);
	end component jpeg_accelerator;

	u0 : component jpeg_accelerator
		port map (
			clk_clk => CONNECTED_TO_clk_clk  -- clk.clk
		);

