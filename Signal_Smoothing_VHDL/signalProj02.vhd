library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity signalProj02 is
    port (
        clk      : in std_logic;  -- 50MHz clock input
        reset_n  : in std_logic;
        led      : out std_logic_vector(9 downto 0);  -- Updated for DE0-Nano LED pins
        tx       : out std_logic  -- UART transmit line
    );    
end entity;

architecture rtl of signalProj02 is
    -- ADC component declaration remains the same
    
    component adc0 is
        port (
            CLOCK : in  std_logic;
            RESET : in  std_logic;
            CH0   : out std_logic_vector(11 downto 0)
        );
    end component adc0;

    -- Constants for sampling rate and UART
    constant SAMPLE_RATE_DIVIDER : integer := 1134;  -- Adjusted for a 4kHz sampling rate
    constant CLKS_PER_BIT : integer := 25;  -- For 2M baud rate with 50MHz clock

    -- Sampling control signals
    signal sample_timer : integer range 0 to SAMPLE_RATE_DIVIDER-1 := 0;
    signal sample_tick  : std_logic := '0';

    -- Signals for ADC and LED control
    signal adc_value : std_logic_vector(11 downto 0);
    signal led_reg   : std_logic_vector(9 downto 0);  -- Adjusted for 8 LEDs on DE0-Nano
    signal amplified_value : unsigned(11 downto 0);

    -- Moving average filter signals
    type sample_array is array (0 to 99) of unsigned(11 downto 0);
    signal samples : sample_array := (others => (others => '0'));
    signal sample_sum : unsigned(18 downto 0) := (others => '0');
    signal sample_index : integer range 0 to 99 := 0;
    signal filtered_value : unsigned(11 downto 0);

    -- UART signals
    type uart_state_type is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
    signal uart_state : uart_state_type := IDLE;
    signal clk_count : integer range 0 to CLKS_PER_BIT-1 := 0;
    signal bit_index : integer range 0 to 7 := 0;
    signal tx_data   : std_logic_vector(7 downto 0) := (others => '0');
    signal uart_send_trigger : std_logic := '0';
    signal byte_select : integer range 0 to 1 := 0;

begin
    u0 : adc0
        port map (
            CLOCK => clk,
            RESET => '0',
            CH0   => adc_value
        );

    -- Sample rate generator
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            sample_timer <= 0;
            sample_tick <= '0';
        elsif rising_edge(clk) then
            sample_tick <= '0';
            if sample_timer = SAMPLE_RATE_DIVIDER-1 then
                sample_timer <= 0;
                sample_tick <= '1';  -- Generate sampling pulse
            else
                sample_timer <= sample_timer + 1;
            end if;
        end if;
    end process;

    -- Main ADC processing with moving average filter
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            led_reg <= (others => '0');
            amplified_value <= (others => '0');
            uart_send_trigger <= '0';
            samples <= (others => (others => '0'));
            sample_sum <= (others => '0');
            sample_index <= 0;
        elsif rising_edge(clk) then
            uart_send_trigger <= '0';  -- Default state

            if sample_tick = '1' then  -- Process on sample tick
                -- Update the sample array and sum for moving average
                sample_sum <= sample_sum - samples(sample_index) + unsigned(adc_value);
                samples(sample_index) <= unsigned(adc_value);

                -- Update index and wrap around
                if sample_index = 99 then
                    sample_index <= 0;
                else
                    sample_index <= sample_index + 1;
                end if;

                -- Calculate the filtered value (average)
                filtered_value <= sample_sum(18 downto 7);  -- Divide by 100
                amplified_value <= filtered_value;

                uart_send_trigger <= '1';  -- Trigger UART transmission

                -- Update LED display based on the filtered value
                led_reg <= std_logic_vector(filtered_value(11 downto 2));
            end if;
        end if;
    end process;

    -- UART transmission
    process(clk)
    begin
        if rising_edge(clk) then
            case uart_state is
                when IDLE =>
                    tx <= '1';
                    if uart_send_trigger = '1' then
                        if byte_select = 0 then
                            tx_data <= std_logic_vector(filtered_value(11 downto 4));
                        else
                            tx_data <= std_logic_vector(filtered_value(3 downto 0)) & "0000";
                        end if;
                        uart_state <= START_BIT;
                        clk_count <= 0;
                    end if;

                when START_BIT =>
                    tx <= '0';
                    if clk_count = CLKS_PER_BIT-1 then
                        clk_count <= 0;
                        uart_state <= DATA_BITS;
                        bit_index <= 0;
                    else
                        clk_count <= clk_count + 1;
                    end if;

                when DATA_BITS =>
                    tx <= tx_data(bit_index);
                    if clk_count = CLKS_PER_BIT-1 then
                        clk_count <= 0;
                        if bit_index = 7 then
                            uart_state <= STOP_BIT;
                        else
                            bit_index <= bit_index + 1;
                        end if;
                    else
                        clk_count <= clk_count + 1;
                    end if;

                when STOP_BIT =>
                    tx <= '1';
                    if clk_count = CLKS_PER_BIT-1 then
                        clk_count <= 0;
                        uart_state <= IDLE;
                        if byte_select = 0 then
                            byte_select <= 1;
                        else
                            byte_select <= 0;
                        end if;
                    else
                        clk_count <= clk_count + 1;
                    end if;
            end case;
        end if;
    end process;

    -- Assign LED output
    led <= led_reg;

end architecture;
