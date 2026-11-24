#include <stdio.h>
#include "pico/stdlib.h"
#include "hardware/i2c.h"
#include <iostream>

/////////////////////////
//
// Hard coded variables
//
/////////////////////////

#define Debug false

// MPU6050 (Vertical)
#define MPU6050_0_SDA 6
#define MPU6050_0_SCL 7
#define MPU6050_0_I2C i2c1

// MPU6050 (Horizontal)
#define MPU6050_1_SDA 12
#define MPU6050_1_SCL 13
#define MPU6050_1_I2C i2c0

// BMP280
#define BMP280_SDA 14
#define BMP280_SCL 15
#define BMP280_I2C i2c1

// GPS
#define GPS_TX 16
#define GPS_RX 17
#define GPS_UART uart0
#define GPS_BAUD_RATE 9600
#define BUFFER_SIZE 128

// NRF24L01



/////////////////////////
//
// Classes
//
/////////////////////////

class StateHandler;
class State {
public:
    virtual ~State() {}
    virtual void enter(StateHandler& context) = 0;
    virtual void update(StateHandler& context) = 0;
    virtual void exit(StateHandler& context) = 0;
};

class StateHandler {
public:
    void SetState(State *NewState) {
        currentState = NewState;
    }

    void HandleUpdate() {
        currentState->update(*this);
    }


private:
    State* currentState = nullptr;
};


/////////////////////////
//
// Variables
//
/////////////////////////

static StateHandler handler;



void init() {
    stdio_init_all();

    // MPU6050_0
    i2c_init(MPU6050_0_I2C, 400 * 1000);
    gpio_set_function(MPU6050_0_SDA, GPIO_FUNC_I2C);
    gpio_set_function(MPU6050_0_SCL, GPIO_FUNC_I2C);
    gpio_pull_up(MPU6050_0_SDA);
    gpio_pull_up(MPU6050_0_SCL);

    //MPU6050_1
    i2c_init(MPU6050_1_I2C, 400 * 1000);
    gpio_set_function(MPU6050_1_SDA, GPIO_FUNC_I2C);
    gpio_set_function(MPU6050_1_SCL, GPIO_FUNC_I2C);
    gpio_pull_up(MPU6050_1_SDA);
    gpio_pull_up(MPU6050_1_SCL);

    // BMP280
    i2c_init(BMP280_I2C, 100 * 1000);
    gpio_set_function(BMP280_SDA, GPIO_FUNC_I2C);
    gpio_set_function(BMP280_SCL, GPIO_FUNC_I2C);
    gpio_pull_up(BMP280_SDA);
    gpio_pull_up(BMP280_SCL);

    // GPS
    uart_init(GPS_UART, GPS_BAUD_RATE);
    gpio_set_function(GPS_RX, GPIO_FUNC_UART);
    gpio_set_function(GPS_TX, GPIO_FUNC_UART);
    uart_set_hw_flow(GPS_UART, false, false);
    uart_set_format(GPS_UART, 8, 1, UART_PARITY_NONE);
    uart_set_fifo_enabled(GPS_UART, true);

}


int main() {
    init();
    sleep_ms(5000);

    while (true) {
        handler.HandleUpdate();
    }
    return 0;
}