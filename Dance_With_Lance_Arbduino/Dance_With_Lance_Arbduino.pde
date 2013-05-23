/**** Split-rail Pedalometer
* Arduino code to run the Dance with Lance Arbduino
* ver. 1.9
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
* Australia - changed pin numbers to match specific Arbduino setup
*/

char versionStr[] = "AC Power Pedal Power Utility Box ver. 1.10";

/*

Check the system voltage. 
Establish desired LED behavior for current voltage.
Do the desired behavior until the next check.

Repeat. 

*/

// GLOBAL VARIABLES
const int AVG_CYCLES = 50; // average measured voltage over this many samples
const int DISPLAY_INTERVAL_MS = 500; // when auto-display is on, display every this many milli-seconds
const int BLINK_PERIOD = 600;
const int FAST_BLINK_PERIOD = 150;
const int LED_UPDATE_INTERVAL = 500;

// STATE CONSTANTS
const int STATE_OFF = 0;
const int STATE_BLINK = 1;
const int STATE_BLINKFAST = 3;
const int STATE_ON = 2;

// PINS
const int relayPin = 13; // relay cutoff output pin
const int voltPin = A0; // Voltage Sensor Pin
const int ampsPin = A1; // Current Sensor Pin
const int numLeds = 7; // Number of LED outputs.
int ledPins[numLeds] = {2, 3, 4, 5, 6, 7, 8}; 
// levels at which each LED turns on (not including special states)
float ledLevels[numLeds] = {24.0, 28.0, 32.0, 36.0, 40.0, 44.0, 48.0};
// current active level
int ledLevel = -1;
// on/off/blink/fastblink state of each led 
int ledState[numLeds] = {STATE_OFF};

// SPECIAL STATE 
const float MAX_VOLTS = 50.0;  // 
const float RECOVERY_VOLTS = 40.0;
int relayState = STATE_OFF;

const float DANGER_VOLTS = 52.0;
int dangerState = STATE_OFF;

int blinkState = 0;
int fastBlinkState = 0;



const float voltcoeff = 13.25;  // larger numer interprets as lower voltage 
//const float ampcoeff = 7.4; // see adc2amps()


// vars to store temp values

//Voltage related variables. 
int voltsAdc = 0;
float voltsAdcAvg = 0;
float volts = 0;

//Current related variables
int ampsAdc = 0;
float ampsAdcAvg = 0;
float amps = 0;

float watts = 0;


int readCount = 0; // for determining how many sample cycle occur per display interval


// timing variables for various processes: led updates, print, blink, etc 
unsigned long time = 0;
unsigned long timeFastBlink = 0;
unsigned long timeBlink = 0;
unsigned long timeRead = 0;
unsigned long timeDisplay = 0;
unsigned long timeLeds = 0;


// var for looping through arrays
int i = 0;
int x = 0;
int y = 0;


void setup() {
  Serial.begin(57600);

  Serial.println(versionStr);
  
  pinMode(voltPin,INPUT);
  pinMode(ampsPin,INPUT);
  
  pinMode(relayPin, OUTPUT);
  digitalWrite(relayPin,LOW);
 
  // init LED pins
  for(i = 0; i < numLeds; i++) {
    pinMode(ledPins[i],OUTPUT);
    digitalWrite(ledPins[i],LOW);
  }
}

//int senseLevel = -1;

void loop() {

  getVolts();
  calcVolts();
  doSafety();
  
  getAmps();
  
  readCount++;

  time = millis();

  doBlink();
  
  if(time - timeLeds > LED_UPDATE_INTERVAL){
    doLeds();
    timeLeds = time;
  }
    
    //Now show the - Team how hard to pedal. 
    
  if(time - timeDisplay > DISPLAY_INTERVAL_MS){
    timeDisplay = time;
    //printDisplay();
    printWatts();
    readCount = 0;
  }
  
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

  for(i = 0; i < numLeds; i++) {
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
    for(i = 0; i < numLeds; i++) {
      ledState[i] = STATE_BLINKFAST;
    }
  }    
  
  // if at the top level, blink it fast
  if (ledLevel == (numLeds-1)){
    ledState[ledLevel-1] = STATE_BLINKFAST; 
  }
      
    // Do the desired states. 
    // loop through each led and turn on/off or adjust PWM
                
  for(i = 0; i < numLeds; i++) {
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


int ampsCompensation = 0;
void getAmps(){
  ampsAdc = analogRead(ampsPin);
  ampsAdc = ampsAdc + ampsCompensation;
  ampsAdcAvg = average(ampsAdc, ampsAdcAvg);
}
void calcAmps(){
    amps = adc2amps(ampsAdcAvg);
}


void getVolts(){
  voltsAdc = analogRead(voltPin);
  voltsAdcAvg = average(voltsAdc, voltsAdcAvg);
}
void calcVolts(){
    volts = adc2volts(voltsAdcAvg);
}

float average(float val, float avg){
  if(avg == 0)
    avg = val;
  return (val + (avg * (AVG_CYCLES - 1))) / AVG_CYCLES;
}

static int volts2adc(float v){
 /* voltage calculations
*
* Vout = Vin * R2/(R1+R2), where R1 = 100k, R2 = 10K
* 30V * 10k/110k = 2.72V // at ADC input, for a 55V max input range
*
* Val = Vout / 5V max * 1024 adc val max (2^10 = 1024 max vaue for a 10bit ADC)
* 2.727/5 * 1024 = 558.4896
*/
//int led3volts0 = 559;

/* 24v
* 24v * 10k/110k = 2.181818181818182
* 2.1818/5 * 1024 = 446.836363636363636
*/
//int led2volts4 = 447;

//adc = v * 10/110/5 * 1024 == v * 18.618181818181818;

return v * voltcoeff;
}



float adc2volts(float adc){
  // v = adc * 110/10 * 5 / 1024 == adc * 0.0537109375;
  return adc * (1 / voltcoeff); // 55 / 1024 = 0.0537109375;
}

float adc2amps(float adc){
    // A/adc = 0.1220703125 A/adc
  return (adc - 512) * 0.1220703125;
  //return adc * (1 / ampcoeff); 
}

void calcWatts(){
  calcAmps();
  calcVolts();
  watts = volts * amps;
}

void printWatts(){
  calcWatts();
  Serial.print("w");
  Serial.println(watts); 
}

//void printDisplay(){
//  Serial.print("volts: ");
//  Serial.print(voltage);
//    Serial.print(", AC Amps: ");
//  Serial.print(plusRailAmps);
//
//  Serial.print(", Levels ");
//  for(i = 0; i < numLevels; i++) {
//    Serial.print(i);
//    Serial.print(": ");
//    Serial.print(state[i]);
//    Serial.print(", ");
//  }
//  
//  Serial.println("");
//  Serial.println();
//  
//}
