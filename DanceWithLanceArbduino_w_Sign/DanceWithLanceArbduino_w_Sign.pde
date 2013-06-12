/**** Single-rail Pedalometer
* Arduino code to run the Dance with Lance Arbduino
* ver. 1.14
* Written by:
* Thomas Spellman <thomas@thosmos.com>
* Jake <jake@spaz.org>
* Paul@rockthebike.com
*
* Notes:
* 1.6 - moved version to the top, started protocol of commenting every change in file and in Git commit
* 1.7 - jake 6-21-2012 disable minusalert until minus rail is pedaled at least once (minusAlertEnable and startupMinusVoltage)
* 1.8 -- FF added annoying light sequence for when relay fails or customer bypasses protection circuitry.+
* 1.9 - TS => cleaned up a bit, added state constants, turn off lowest 2 levels when level 3 and above
* 1.10 - TS => cleaned up levels / pins variables, changed to a "LEDs" naming scheme
* 1.11 - TS => does a very slow 4digits watts average, fixed the high blink
* 1.12 - TS => printWatts uses D4Avg instead of watts, 300 baud
* 1.13 - TS => D4Avg fix, 2400 baud
* 1.14 - FF => Added CalcWattHours function, changing the Sign's data to Watt Hours, instead of Watts, in time for BMF VII*/

char versionStr[] = "AC Power Pedal Power Utility Box ver. 1.14. For best results connect the Sign!";

/*

Check the system voltage.
Establish desired LED behavior for current voltage.
Do the desired behavior until the next check.

Repeat.

*/

// FAKE AC POWER VARIABLES
const int knobPin = A2;
int knobAdc = 0;
void doKnob(){
  knobAdc = analogRead(knobPin);
}

// GLOBAL VARIABLES
const int AVG_CYCLES = 50; // average measured values over this many samples
const int DISPLAY_INTERVAL = 2000; // when auto-display is on, display every this many milli-seconds
const int LED_UPDATE_INTERVAL = 1000;
const int D4_AVG_PERIOD = 10000;
const int BLINK_PERIOD = 600;
const int FAST_BLINK_PERIOD = 150;

// STATE CONSTANTS
const int STATE_OFF = 0;
const int STATE_BLINK = 1;
const int STATE_BLINKFAST = 3;
const int STATE_ON = 2;

// LEDS
const int NUM_LEDS = 7; // Number of LED outputs.
// levels at which each LED turns on (not including special states)
float ledLevels[NUM_LEDS] = {24.0, 28.0, 32.0, 36.0, 40.0, 44.0, 48.0};
// current active level
int ledLevel = -1;
// on/off/blink/fastblink state of each led
int ledState[NUM_LEDS] = {STATE_OFF};

// PINS
const int relayPin = 13; // relay cutoff output pin
const int voltPin = A0; // Voltage Sensor Pin
const int ampsPin = A3; // Current Sensor Pin
const int ledPins[NUM_LEDS] = {2, 3, 4, 5, 6, 7, 8};

// SPECIAL STATE
const float MAX_VOLTS = 50.0;  //
const float RECOVERY_VOLTS = 40.0;
int relayState = STATE_OFF;

const float DANGER_VOLTS = 52.0;
int dangerState = STATE_OFF;

int blinkState = 0;
int fastBlinkState = 0;

const float voltcoeff = 13.25;  // larger number interprets as lower voltage

//Voltage related variables.
int voltsAdc = 0;
float voltsAdcAvg = 0;
float volts = 0;

//Current related variables
int ampsAdc = 0;
float ampsAdcAvg = 0;
float amps = 0;

float watts = 0;
float wattHours = 0;

int readCount = 0; // for determining how many sample cycle occur per display interval
int avgCount = 0;
volatile float D4Avg = 0.0;
float D4AvgCycles = 0;
boolean D4Initted = false;

// timing variables for various processes: led updates, print, blink, etc
unsigned long time = 0;
unsigned long timeFastBlink = 0;
unsigned long timeBlink = 0;
unsigned long timeRead = 0;
unsigned long timeDisplay = 0;
unsigned long timeLeds = 0;
unsigned long wattHourTimer = 0;


// var for looping through arrays
int i = 0;
int x = 0;
int y = 0;


void setup() {
  Serial.begin(2400);

  Serial.println(versionStr);

  pinMode(voltPin,INPUT);
  pinMode(ampsPin,INPUT);

  pinMode(relayPin, OUTPUT);
  digitalWrite(relayPin,LOW);

  // init LED pins
  for(i = 0; i < NUM_LEDS; i++) {
    pinMode(ledPins[i],OUTPUT);
    digitalWrite(ledPins[i],LOW);
  }

  timeDisplay = millis();
}

//int senseLevel = -1;

void loop() {

  getVolts();
  doSafety();

  getAmps();

  readCount++;

  calcWatts();
  
//  if it's been 1 seconds since the last time we measured Watt Hours...
if (millis() % 1000 == 0) {
  calcWattHours();
}

  if(avgCount > AVG_CYCLES && D4Initted){
    //tmpD4Avg = D4average(watts, D4Avg);
    D4average();
//    Serial.print("recalc watts: ");
//    Serial.print(watts);
//    Serial.print(", tmpD4Avg: ");
//    Serial.println(tmpD4Avg);
//    Serial.print("recalcing D4Avg: ");
//    Serial.println(D4Avg);
    avgCount = 0;
    //D4Avg = tmpD4Avg;
  }

  time = millis();

  // blink the LEDs
  doBlink();

  doLeds();

  //Now show the - Team how hard to pedal.
  if(time - timeDisplay > DISPLAY_INTERVAL){

    //Serial.println("display");
    // set up the 4D avg cycles
    if(!D4Initted){
      D4AvgCycles = (30.0 * (float)readCount) / (float)AVG_CYCLES;
      Serial.print("readCount: ");
      Serial.println(readCount);
      Serial.print("D4AvgCycles: ");
      Serial.println(D4AvgCycles);
      D4Initted = true;
    }
// printWatts();
  printWattHours();
    //printDisplay();
    //readCount = 0;
    timeDisplay = time;
  }

}

float p1, p2, p3 = 0.0;

float D4average(){
  if(D4Avg < 0.01)
    D4Avg = 0.01;
//  Serial.print("D4average: watts: ");
//  Serial.print(watts);
//  Serial.print(", D4Avg: ");
//  Serial.print(D4Avg);
//  Serial.print(", D4AvgCycles: ");
//  Serial.print(D4AvgCycles);
//  if(avg == 0.0)
//    avg = val;
  p1 = D4Avg * (D4AvgCycles - 1);
//  Serial.print(", p1: ");
//  Serial.println(p1);
  p2 = watts + p1;
//  Serial.print(", p2: ");
//  Serial.println(p2);
  p3 = p2 / D4AvgCycles;
//  Serial.print(", p3: ");
//  Serial.println(p3);
  //return p3;
  D4Avg = p3;
}


void doSafety() {
   if (volts > MAX_VOLTS){
     digitalWrite(relayPin, HIGH);
     relayState = STATE_ON;
  }

  if (relayState == STATE_ON && volts < RECOVERY_VOLTS){
     digitalWrite(relayPin, LOW);
     relayState = STATE_OFF;
  }

  if (volts > DANGER_VOLTS){
     dangerState = STATE_ON;
  } else {
     dangerState = STATE_OFF;
  }
}

void doBlink(){

    if (((time - timeBlink) > BLINK_PERIOD) && blinkState == 1){
            blinkState = 0;
            timeBlink = time;
          } else if (((time - timeBlink) > BLINK_PERIOD) && blinkState == 0){
             blinkState = 1;
             timeBlink = time;
          }


    if (((time - timeFastBlink) > FAST_BLINK_PERIOD) && fastBlinkState == 1){
            fastBlinkState = 0;
            timeFastBlink = time;
          } else if (((time - timeFastBlink) > FAST_BLINK_PERIOD) && fastBlinkState == 0){
              fastBlinkState = 1;
             timeFastBlink = time;
          }

}

void doLeds(){

  // Set the desired lighting states.

  ledLevel = -1;

  for(i = 0; i < NUM_LEDS; i++) {
    if(volts >= ledLevels[i]){
      ledLevel = i;
      ledState[i]=STATE_ON;
    }
    else
      ledState[i]=STATE_OFF;
  }

  // if voltage is below the lowest level, blink the lowest level
  if (volts < ledLevels[0]){
    ledLevel=0;
    ledState[0]=STATE_BLINK;
  }

  // turn off first 2 levels if voltage is above 3rd level
  if(volts > ledLevels[2]){
    ledState[0] = STATE_OFF;
    ledState[1] = STATE_OFF;
  }

  if (dangerState){
    for(i = 0; i < NUM_LEDS; i++) {
      ledState[i] = STATE_BLINKFAST;
    }
  }

  // if at the top level, blink it fast
  if (ledLevel == (NUM_LEDS-1)){
    ledState[ledLevel] = STATE_BLINKFAST;
  }

    // Do the desired states.
    // loop through each led and turn on/off or adjust PWM

  for(i = 0; i < NUM_LEDS; i++) {
    if(ledState[i]==STATE_ON){
      digitalWrite(ledPins[i], HIGH);
    }
    else if (ledState[i]==STATE_OFF){
      digitalWrite(ledPins[i], LOW);
    }
    else if (ledState[i]==STATE_BLINK && blinkState==1){
     digitalWrite(ledPins[i], HIGH);
    }
    else if (ledState[i]==STATE_BLINK && blinkState==0){
     digitalWrite(ledPins[i], LOW);
    }
    else if (ledState[i]==STATE_BLINKFAST && fastBlinkState==1){
     digitalWrite(ledPins[i], HIGH);
    }
    else if (ledState[i]==STATE_BLINKFAST && fastBlinkState==0){
     digitalWrite(ledPins[i], LOW);
    }
  }

} // END doLeds()


int ampsCompensation = 2;
void getAmps(){
  ampsAdc = analogRead(ampsPin);
  ampsAdc = analogRead(ampsPin);
  ampsAdc = analogRead(ampsPin);
  ampsAdc = ampsAdc + ampsCompensation;
  ampsAdcAvg = average(ampsAdc, ampsAdcAvg);
  amps = adc2amps(ampsAdcAvg);
  avgCount++;
}


void getVolts(){
  voltsAdc = analogRead(voltPin);
  voltsAdcAvg = average(voltsAdc, voltsAdcAvg);
  volts = adc2volts(voltsAdcAvg);
}

float average(float val, float avg){
  if(avg == 0)
    avg = val;
  return (val + (avg * (AVG_CYCLES - 1))) / AVG_CYCLES;
}

static int volts2adc(float v){

//adc = v * 10/110/5 * 1024 == v * 18.618181818181818;

return v * voltcoeff;
}



float adc2volts(float adc){
  // v = adc * 110/10 * 5 / 1024 == adc * 0.0537109375;
  return adc * (1 / voltcoeff); // 55 / 1024 = 0.0537109375;
}

// amp sensor conversion factors
// 0A == 512 adc == 1.65pV // current sensor offset
// pV/A = .04 pV/A (@5V) * 3.3V/5V = .0264 pV/A (@3.3V) // sensor sensitivity (pV = adc input pin volts)
// adc/pV = 1024 adc / 3.3 pV = 310.3030303030303 adc/pV  // adc per pinVolt
// adc/A = 310.3030303030303 adc/pV * 0.0264 pV/A = 8.192 adc/A
// A/adc = 1 A / 8.192 adc = 0.1220703125 A/adc

float adc2amps(float adc){
    // A/adc = 0.1220703125 A/adc
  return (adc - 512) * 0.1220703125;
  //return adc * (1 / ampcoeff);
}

void calcWatts(){
  watts = volts * amps;
  doKnob();
  watts += knobAdc / 2;
  //Serial.print("calcWatts: ");
  //Serial.println(watts);
}

void calcWattHours(){
  wattHours += (int) (D4Avg * 0.0278);
  
  // This code was written to show accumulated Watt Hours at events. The 0.0278 factor is 100 divided by the number of seconds in an hour. 
  // In the main loop you can see that calcWattHours is being told to run every second. The number printed to the sign is actual watt hours * 10. 
  // So if it says 58, you can tell the pedaler, "you just pedaled 5.8 WattHours. Thanks!" 
  // Before BMF, change the factor to 0.00278. Then the number printed on the Sign will be actual Watt Hours.   
}

void printWatts(){
  Serial.print("w");
  Serial.println(D4Avg);
}

void printWattHours(){
  Serial.print("w");
  Serial.println(wattHours);
}

void printDisplay(){
  Serial.print("v: ");
  Serial.print(volts);
  Serial.print(", a: ");
  Serial.print(amps);
  Serial.print(", va: ");
  Serial.print(watts);

//  Serial.print(", Levels ");
//  for(i = 0; i < NUM_LEDS; i++) {
//    Serial.print(i);
//    Serial.print(": ");
//    Serial.print(ledState[i]);
//    Serial.print(", ");
//  }
//  Serial.println("");
  Serial.println();

}
