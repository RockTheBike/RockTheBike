#define baudrate 2400
#define CLEAR_TIME 175 // 150 is fine
#define SET_TIME 150 // 150 is fine
#define PEDAL_VOLT 3 // voltage below which sign says PEDAL
#define CHILL_VOLT 48 // voltage above which sign says CHILL
#define HYSTERESIS 1 // voltage distance before sign switches back to wattage mode

/*

 http://upload.wikimedia.org/wikipedia/commons/thumb/0/02/7_segment_display_labeled.svg/220px-7_segment_display_labeled.svg.png
 
 Our sign stays where you set it when you don"t do anything.
 We just FLIP the segments once a second.
 
 pins 2345678 are segments abcdefg of a digit
 These are active HIGH, so if you want a segment to glow,
 you make the corresponding pins HIGH.
 
 pins 10,11,12,13 are the thousands, hundreds, tens, and ones DIGITS.
 And when they are HIGH, they are inactive.
 You must make these HIGH first thing in the setup of your program
 
 pins A5 and A6 are for making the 5th digit say P or C respectively.
 They go HIGH to cause that letter to appear.
 
 pin 9 is "all clear" and makes all the signs go blank.  You must have this
 pin HIGH at the beginning of all updates for at least 150mS.  Then you set it
 LOW and keep the digit active, with the selected segments still HIGH, for 
 another 150mS at least.
 
 you must make all these pins OUTPUTS first thing in the program
 
 once a second, read amperage and voltage and get wattage,
 and set the display to the wattage.
 
 and print amperage, voltage, and their corresponding ADC values
 (the exact values you read to get those results) and wattage
 to the serial port 57600 baud.  All in one line.
 
 the serial protocol is, it waits for a recognized mode constant like
 'w' (for wattage) and then starts grabbing numeric ASCII digits (up to four
 of them), or a non-numeric character, and then it updates the sign to show
 the numbers it was sent (right justified with leading blank digits).
 Up to 9999 is a valid number.
 
 for example, w123 will display " 123" on the sign 
 */

#define NUM_DIGITS 4
int digitPins[NUM_DIGITS] = { 
  13, 12, 11, 10 };

int digitWas[NUM_DIGITS] = { // what was the digit last time
  0,0,0,0};

#define NUM_SEGMENTS 7
int segmentPins[NUM_SEGMENTS] = { 
  2, 3, 4, 5, 6, 7, 8 };

#define VOLT_PIN A0
#define AMP_PIN A3
#define AMP_OFFSET 512
#define AMP_SCALE 1
#define VOLT_SCALE 13.479
#define CLEAR_PIN 9
#define PEDAL_PIN A6
#define PEDAL_PIN2 A2
#define CHILL_PIN A1

unsigned long wattage = 1234; // for testing

unsigned long lastUpdate = 0; // last time we put up PEDAL or CHILL
#define updateTime 3000 // how often to update sign

const char wattChar = 'w';  // character which precedes a numerical wattage value in serial data
int dataCount = 0;         // counts how many digits received before non-digit
int dataIndex = 0;         // which digit are we updating right now?
int data[5] = {
  0,0,0,0,0};  // the numeric data imported from the serial port (first record is data type, like wattage or voltage)
char inByte = 0;         // incoming serial byte
int dataReady = true;  // true when data arrives, cleared when display updated.

#define WATTS_STATE 0
#define PEDAL_STATE 1
#define CHILL_STATE 2

int state = WATTS_STATE; 

int numbers[10][7] = {
  { 
    1, 1, 1, 1, 1, 1, 0                                                                                                                                                                                                                                                                                                                       }
  , // 0
  { 
    0, 1, 1, 0, 0, 0, 0                                                                                                                                                                                                                                                                                                                       }
  , // 1
  { 
    1, 1, 0, 1, 1, 0, 1                                                                                                                                                                                                                                                                                                                       }
  , // 2
  { 
    1, 1, 1, 1, 0, 0, 1                                                                                                                                                                                                                                                                                                                       }
  , // 3
  { 
    0, 1, 1, 0, 0, 1, 1                                                                                                                                                                                                                                                                                                                       }
  , // 4
  { 
    1, 0, 1, 1, 0, 1, 1                                                                                                                                                                                                                                                                                                                       }
  , // 5
  { 
    1, 0, 1, 1, 1, 1, 1                                                                                                                                                                                                                                                                                                                       }
  , // 6
  { 
    1, 1, 1, 0, 0, 0, 0                                                                                                                                                                                                                                                                                                                       }
  , // 7
  { 
    1, 1, 1, 1, 1, 1, 1                                                                                                                                                                                                                                                                                                                       }
  , // 8
  { 
    1, 1, 1, 1, 0, 1, 1                                                                                                                                                                                                                                                                                                                       }  // 9
};

int pedal[4][7] = {
  { 
    1, 0, 0, 1, 1, 1, 1                                                                                                                                                                                                                                                                                                                       }
  , // E
  { 
    1, 1, 1, 1, 1, 1, 0                                                                                                                                                                                                                                                                                                                       }
  , // D
  { 
    1, 1, 1, 0, 1, 1, 1                                                                                                                                                                                                                                                                                                                       }
  , // A
  { 
    0, 0, 0, 1, 1, 1, 0                                                                                                                                                                                                                                                                                                                       }  // L
};

int chill[4][7] =  { 
  { 
    0, 1, 1, 0, 1, 1, 1                                                                                                                                                                                                                                                                                                                       }
  , // H
  { 
    0, 0, 0, 0, 1, 1, 0                                                                                                                                                                                                                                                                                                                       }
  , // I
  { 
    0, 0, 0, 1, 1, 1, 0                                                                                                                                                                                                                                                                                                                       }
  , // L
  { 
    0, 0, 0, 1, 1, 1, 0                                                                                                                                                                                                                                                                                                                       }  // L
};


void setup() {
  Serial.begin(baudrate);
  Serial.println("Wattmetery");

  for (int i = 0; i < NUM_SEGMENTS; ++i) {
    pinMode(segmentPins[i], OUTPUT);
    digitalWrite(segmentPins[i], LOW);
  }

  for (int i = 0; i < NUM_DIGITS; ++i) {
    pinMode(digitPins[i], OUTPUT);
    digitalWrite(digitPins[i], HIGH);
  }

  pinMode(PEDAL_PIN, OUTPUT);
  pinMode(PEDAL_PIN2, OUTPUT);
  pinMode(CHILL_PIN, OUTPUT);
  pinMode(CLEAR_PIN, OUTPUT);
}

void checkSerial() {
  if (Serial.available() > 0) {
    inByte = Serial.read();
    //    Serial.print(inByte);
    if (inByte == wattChar) { // the wattage is being sent!
      dataIndex = 0;
      dataCount = 0;
      data[dataIndex++] = (int)wattChar;  // data[0] holds mode value (in future, mutliple modes)
      return;  // leave checkSerial(), we got our byte
    }
    if ((dataIndex > 0) && (dataIndex <= 4)) {
      if ((inByte >= '0') && (inByte <= '9')) {
        data[dataIndex++] = inByte - 48;  // put the numeric value of the digit into data[]
        //        Serial.print(inByte);
        dataCount++;  // how many digits have we collected?
      }
      else dataIndex = 5;  // if a non-number character, we got our data
    } 
  }

  if ((dataIndex == 5) && (dataCount > 0)) {  // move the collected numerology to the digits array
    int scale = 1;
    for (int i = 1; i < dataCount; i++) scale *= 10; // if dataCount == 1 this doesnt even run once
    wattage = 0;
    for (int i = 0; i < dataCount; i++) {
      wattage += (data[i+1] * scale);
      //      Serial.print(data[i+1]);
      //      Serial.println(scale);
      scale /= 10;
    }
    dataIndex = 0;
    dataCount = 0;
    dataReady = true; // we got new data
    //    Serial.println(wattage);
  }
}

void clearSegments() {
  for (int i = 0; i < NUM_SEGMENTS; ++i) {
    digitalWrite(segmentPins[i], LOW);
  }  
}

void writeSegments(int* segments) {
  if (!segments) return;

  for (int i = 0; i < NUM_SEGMENTS; ++i) {
    digitalWrite(segmentPins[i], segments[i]);
    //Serial.println(segmentPins[i]);
    //Serial.println(segments[i]);
  }  
}

void writeDigit(int digitPin, int* segments) {
  //Serial.println(digitPin);
  //  clearSegments(); // digitalwrite all low
  if (segments) {
    writeSegments(segments);
  } 
  else {
    clearSegments();
    //    Serial.print("x");
  }
  if (segments == chill[0]) digitalWrite(CHILL_PIN, HIGH); // set 5th digit to "C"
  if (segments == pedal[0]) digitalWrite(PEDAL_PIN, HIGH); // set 5th digit to "P"
  if (segments == pedal[0]) digitalWrite(PEDAL_PIN2, HIGH); // set 5th digit to "P"
  digitalWrite(digitPin, LOW);
  digitalWrite(CLEAR_PIN, HIGH);  
  delay(CLEAR_TIME);
  digitalWrite(CLEAR_PIN, LOW);  
  if (segments)  delay(SET_TIME);
  if (segments == pedal[0]) delay(SET_TIME); // give extra time for letter P
  digitalWrite(PEDAL_PIN, LOW);
  digitalWrite(PEDAL_PIN2, LOW);
  digitalWrite(CHILL_PIN, LOW);
  digitalWrite(digitPin, HIGH);
}

void clearDigits() {
  for (int i = 0; i < NUM_DIGITS; ++i) {
    writeDigit(digitPins[i], NULL);
  }
}

void loop() {
  checkSerial();

  int ampraw = analogRead(AMP_PIN);
  float amperage = (ampraw + AMP_OFFSET) / AMP_SCALE;
  int voltraw = analogRead(VOLT_PIN);
  float voltage = voltraw / VOLT_SCALE;
  //  float wattage = voltage * amperage;

  //  voltage = 34;
  //  wattage = ((wattage * 10) % 10000) + (((wattage % 10) + 1) % 10);
  /*  wattage += 1;
   if (wattage > 12)  wattage += 9;
   if (wattage > 130)  wattage += 90;
   wattage %= 10000;
   */

  if ((voltage < PEDAL_VOLT) && (state != PEDAL_STATE)) {
    //  if (wattage > 6000) { // for testing
    //    Serial.println("pedal");
    for (int i = 0; i < NUM_DIGITS; ++i) {
      writeDigit(digitPins[i], pedal[i]); // EDAL (PEDAL)
    }
    state = PEDAL_STATE;
    lastUpdate = millis();    
  } 
  else if ((voltage > CHILL_VOLT) && (state != CHILL_STATE)) {
    //  else if ((wattage < 4000) && (wattage > 1000)) {   // for testing
    //    Serial.println("chill");    
    for (int i = 0; i < NUM_DIGITS; ++i) {
      writeDigit(digitPins[i], chill[i]); // HILL (CHILL)
    }
    state = CHILL_STATE;
    lastUpdate = millis();
  }  

  if (millis() - lastUpdate > updateTime) if ((state == CHILL_STATE) || (state == PEDAL_STATE)) state = 7;  // make sign re-update word

  if ((voltage <= (CHILL_VOLT - HYSTERESIS)) && (voltage >= (PEDAL_VOLT + HYSTERESIS)) && (state != WATTS_STATE)) {
    state = WATTS_STATE;
    dataReady = true;
  }

  /*    int scale = 1;
   for (int i = 0; i < NUM_DIGITS; ++i) {
   writeDigit(digitPins[i], numbers[(int)(wattage / scale) % 10]);
   scale *= 10;
   } */


  if ((dataReady == true) && (state == WATTS_STATE)) {
    //    Serial.println("watts");    
    if (wattage > 999) writeDigit(digitPins[0],numbers[(int)(wattage / 1000) % 10]);
    else  writeDigit(digitPins[0],NULL);
    if (wattage > 99) writeDigit(digitPins[1],numbers[(int)(wattage / 100) % 10]);
    else  writeDigit(digitPins[1],NULL);
    if (wattage > 9) writeDigit(digitPins[2],numbers[(int)(wattage / 10) % 10]);
    else  writeDigit(digitPins[2],NULL);
    writeDigit(digitPins[3],numbers[(int)(wattage) % 10]);

    dataReady = false; // okay we updated the display
    delay(200);  // take a mandatory rest break
  }
  //  Serial.print(amperage);
  //  Serial.print("A (");
  //  Serial.print(ampraw);
  //  Serial.print(")  ");
  //  Serial.print(voltage);
  //  Serial.print("V (");
  //  Serial.println(voltraw);
  //  Serial.print(")  w=");
  //  Serial.println(wattage);
  //  delay(100);
}

