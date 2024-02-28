#!/usr/bin/python
# -*- coding: latin-1 -*-
# Microtan_FAST_decode.py
# For Python 3
# By J.R.P 05/23
# Based on original code by Zoe Blade
# Converts a .wav file recorded from the Microtan's cassette interface in FAST mode,
# back into the hex byte representation.

import struct  # For converting the (two's complement?) binary data to integers
import sys     # For command line arguments
import wave    # For .wav input and output

# Set defaults
amplitudeThreshold = 0
endianness = "little" # Microtan records in little endian form.
inputFilenames = []

for argument in sys.argv:
    if (argument[-4:].lower() == '.wav'):
        inputFilenames.append(argument)
        continue

if (len(inputFilenames) == 0):
     print("Usage: python3 Microtan_FAST_decode.py input.wav")
     exit()

# Cycle through files
for inputFilename in inputFilenames:
    outputFilenamePrefix = inputFilename[:-4]
    outputFilenameNumber = 0

    try:
         inputFile = wave.open(inputFilename, 'r')
    except Exception as e:
         print(inputFilename, "doesn't look like a valid .wav file. Skipping.")
         print(e)
         continue

    print("Converting", inputFilename, "to binary waveform")

    framerate = inputFile.getframerate()
    numberOfChannels = inputFile.getnchannels()
    sampleWidth = inputFile.getsampwidth()
    print("number of channels = ", inputFile.getnchannels())
    print("sampleWidth = ", inputFile.getsampwidth())
    print("framerate = ", inputFile.getframerate())
    print("number of frames = ", inputFile.getnframes())
    binaryWaveform = {}

    for iteration in range(0, inputFile.getnframes()):
        channelData = inputFile.readframes(1)

        channelNumber = 1
        channelStart = 0
        channelEnd = channelNumber * sampleWidth
        channelValue = struct.unpack('<h', channelData[channelStart:channelEnd])
        sampleValue = channelValue[0]
        ##print ("Value = ", channelValue)
        if (sampleValue >= amplitudeThreshold):
            binaryWaveform[iteration] = True
        else:
            binaryWaveform[iteration] = False

    print("Demodulating", inputFilename, "\n")

    frequencies = {}
    highFrequency = False
    falses = 0
    lastSampleValue = not binaryWaveform[0]
    trueSamples = 0
    samplesInCycle = 0
    zeroCrossings = 0

    data = []
    ##print ("Initial SampleValue = ", lastSampleValue)
    for sampleAddress, sampleValue in binaryWaveform.items():
        ##print(sampleAddress, sampleValue)
        if (lastSampleValue == False and sampleValue == True):
            # Zero crossing. Going positive.
            zeroCrossings +=1
            samplesInCycle +=1
            lastSampleValue = sampleValue
        elif (lastSampleValue == True and sampleValue == False):
            # Zero crossing. Going negative.
            zeroCrossings +=1
            samplesInCycle +=1
            lastSampleValue = sampleValue
        elif (lastSampleValue == sampleValue):
            samplesInCycle +=1

        if (zeroCrossings == 3):
            ##print("SamplesInCycle =",samplesInCycle)
            if (samplesInCycle < 14):
                data.append('1')
            else:
                data.append('0')

            zeroCrossings = 1
            samplesInCycle = 1

#make sure there are no spurious '0' at start of leader signal.
    next = 0
    while data[next] == 0:
        data[next] = '1'
        next+=1
    bitNumber = 0
    lookingForStartBit = True
    lookingForParityBit = False
    bit = 0
    bits = 0
    byte = 0
    n = 0 #copy of 'byte' for parity calculation.
    parityOfByte = 0
    parityStatus = False
    byteCount = 0
    startAddress = 0
    endAddress = 0
    bytesToRead = 0
    checksum = 0
    bytesPrinted = 0
    name = ""
    numOfStopBits = 0

    while bitNumber < len(data):
        if (lookingForStartBit == True):
            if (data[bitNumber] == '0'):
                #start bit found
                lookingForStartBit = False
                # print("\t", numOfStopBits)
                # print (data[bitNumber], end=' ')
                numOfStopBits = 0
            else:
                # print (data[bitNumber], end='')
                numOfStopBits +=1
        elif (bits < 8): # build up a byte.
            # print (data[bitNumber], end='')
            if (data[bitNumber] == '1'):
                bit = 1
            else:
                bit = 0
            byte = (byte >> 1) + (bit * 128)
            bits += 1
        elif (bits == 8): #full byte ready, check parity.
            # print (" ", data[bitNumber], end=' ')
            parityBit = eval(data[bitNumber])
            parityOfByte = 0
            n=byte
            while(n!=0):
                if((n&1)==1):
                    parityOfByte = parityOfByte^1
                n = n>>1
            if (parityOfByte ^ parityBit == 1): #Microtan uses odd parity.
                parityStatus = True
            else:
                parityStatus = False
                print ("Failed! Bad parity at byte ", format(byteCount,'04X'))
                break
            byteCount+=1
            if(byteCount < 9):
                name = name + chr(byte)
            if(byteCount == 9):
                print ("Name = ", name)
                endAddress = byte * 256
            if(byteCount == 10):
                endAddress = endAddress + byte
            if(byteCount == 11):
                startAddress = byte * 256
            if(byteCount == 12):
                startAddress = startAddress + byte
                print("Start address =", format(startAddress, '04X'))
                print("End address =", format(endAddress, '04X'))
                bytesToRead = (endAddress - startAddress)+1
                print("Number of bytes to read =",bytesToRead)
                print("\n")
            if(byteCount-12 > bytesToRead):
                print ("\nData checksum =", format(checksum, '02X'), " Recorded checksum =",
                       format(byte, '02X'))
                if (checksum == byte):
                    print ("Checksum ok")
                else:
                    print ("Checksum failed!")
                break
            if(byteCount > 12):
                checksum = (checksum + byte) & 255
                if (bytesPrinted < 15):
                    print(format(byte,'02X'), end = " ")
                    bytesPrinted += 1
                else:
                    bytesPrinted = 0
                    print(format(byte,'02X'))
            byte = 0
            bits = 0
            lookingForStartBit = True
            numOfStopBits = 0
            parityOfByte = 0
        bitNumber += 1
