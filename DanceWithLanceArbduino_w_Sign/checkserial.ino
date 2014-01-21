 /*
 the serial protocol is, it waits for a recognized mode constant like
 'w' (for wattage) and then starts grabbing numeric ASCII digits (up to four
 of them), or a non-numeric character, and then it updates wattSerial
 Up to 9999 is a valid number.
 
 for example, w123 will set wattSerial to 123
 */
// unsigned long wattSerial = 1234; // must define this in main program

#define WATTCHAR 'w'  // character which precedes a numerical wattage value in serial data
int dataCount = 0;         // counts how many digits received before non-digit
int dataIndex = 0;         // which digit are we updating right now?
int data[5] = {
  0,0,0,0,0};  // the numeric data imported from the serial port (first record is data type, like wattage or voltage)
char inByte = 0;         // incoming serial byte
// int dataReady = true;  // true when data arrives, cleared when display updated.

void checkSerial() {
  if (Serial.available() > 0) {
    inByte = Serial.read();
    if (inByte == WATTCHAR) { // the wattage is being sent!
      dataIndex = 0;
      dataCount = 0;
      data[dataIndex++] = (int)WATTCHAR;  // data[0] holds mode value (in future, mutliple modes)
      return;  // leave checkSerial(), we got our byte
    }
    if ((dataIndex > 0) && (dataIndex <= 4)) {
      if ((inByte >= '0') && (inByte <= '9')) {
        data[dataIndex++] = inByte - 48;  // put the numeric value of the digit into data[]
        dataCount++;  // how many digits have we collected?
      }
      else dataIndex = 5;  // if a non-number character, we got our data
    } 
  }

  if ((dataIndex == 5) && (dataCount > 0)) {  // move the collected numerology to the digits array
    int scale = 1;
    for (int i = 1; i < dataCount; i++) scale *= 10; // if dataCount == 1 this doesnt even run once
    wattSerial = 0;
    for (int i = 0; i < dataCount; i++) {
      wattSerial += (data[i+1] * scale);
      //      Serial.print(data[i+1]);
      //      Serial.println(scale);
      scale /= 10;
    }
    dataIndex = 0;
    dataCount = 0;
    dataReady = true; // we got new data
    //    Serial.println(wattSerial);
  }
}
