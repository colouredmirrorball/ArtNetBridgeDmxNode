
import ch.bildspur.artnet.*;
import ch.bildspur.artnet.packets.*;
import ch.bildspur.artnet.events.*;

import com.heroicrobot.controlsynthesis.*;
import com.heroicrobot.dropbit.common.*;
import com.heroicrobot.dropbit.devices.*;
import com.heroicrobot.dropbit.devices.pixelpusher.*;
import com.heroicrobot.dropbit.discovery.*;
import com.heroicrobot.dropbit.registry.*;

import netP5.*;
import oscP5.*;
import dmxP512.*;
import processing.serial.*;


import java.util.*;


//Art-Net library object, stores incoming messages
ArtNetClient artnet;

OscP5 osc;


//byte[] dmxData = new byte[512];

DeviceRegistry registry;
TestObserver testObserver;

ArrayList<StripOutput> outputs = new ArrayList(8);

boolean display = true;

//String DMXPRO_PORT;//case matters ! on windows port must be upper cased.
int DMXPRO_BAUDRATE=115000;

byte[] dataBuffer = new byte[512];

ArrayList<DmxOutput> dmxOutputs = new ArrayList();

int outputHeight = 70;



void setup()
{
  size(512, 250);
  surface.setLocation(20, 20);
  artnet = new ArtNetClient();
  artnet.start();

  registry = new DeviceRegistry();
  testObserver = new TestObserver();
  registry.addObserver(testObserver);

  //Order:
  //  subnet universe order strip standard/reverse begin end
  String[] args = loadStrings("arguments-bridge.txt");
  int i = 0;
  for (String s : args)
  {
    String[] parse = split(s, ' ');
    if (parse.length > 7)
    {

      StripOutput newOutput = new StripOutput(int(parse[0]), int(parse[1]), int(parse[3]), int(parse[4]));
      int order = StripOutput.RGBW;
      if (parse[2].equalsIgnoreCase("GRB")) order=StripOutput.GRB;
      newOutput.setOrder( order);
      newOutput.setRange(int(parse[6]), int(parse[7]), parse[5].equals("r"));

      outputs.add(newOutput);
    }
  }

  args = loadStrings("arguments-dmx.txt");
  int universe = 0, subnet = 0, startAddress = 0;
  for (String s : args)
  {
    String[] splitted = split(s, '=');
    if (splitted.length == 2)
    {
      if (splitted[0].equalsIgnoreCase("universe")) universe = parseInt(splitted[1]);
      if (splitted[0].equalsIgnoreCase("subnet")) subnet = parseInt(splitted[1]);
      if (splitted[0].equalsIgnoreCase("startaddress")) startAddress = parseInt(splitted[1]);
    }
  }

  int y = 0;

  //find the connected devices, if on Raspi, the device will be called "/dev/ttyUSBX" which we can use to distinguish it from the other serial devices
  //on windows, there should be only one (if you only have the dmx dongle connected)
  for (String s : Serial.list())
  {
    if (s.contains("USB") || (System.getProperty("os.name").startsWith("Windows"))) 
    {
      DmxOutput output = new DmxOutput(this, s, 20+y++*outputHeight);
      output.universe = universe;
      output.subnet = subnet;
      output.startAddress = startAddress;
      dmxOutputs.add(output);
      println("added", s);
    }
  }

  osc = new OscP5(this, 9009);

  println("Added", outputs.size(), "strips");
}

void draw()
{
  background(0);
  noStroke();
  int y = 0;
  for (StripOutput output : outputs)
  {
    output.parseDmx();
    if (display)
    {
      int x = 0;
      int w = width/(output.length+1);
      int h = height/(outputs.size()+1);
      for (color c : output.buffer)
      {
        fill(red(c), green(c), blue(c));
        rect(x, y, w, h);
        x+= w;
      }
      y+=h;
    }
  }

  for (DmxOutput output : dmxOutputs)
  {
    output.update();
  }


  sendPixels();
}


void sendPixels()
{
  if (testObserver.hasStrips) 
  {
    registry.startPushing();
    List<Strip> strips = registry.getStrips();
    for (StripOutput output : outputs)
    {
      if (output != null)
      {
        Strip strip = null;
        for (Strip s : strips)
        {
          if (s.getStripNumber() == output.strip) strip = s;
        }
        if (strip != null)
        {
          for (int stripx = output.beginActual; stripx <= min(strip.getLength(), output.endActual); stripx++) 
          {
            strip.setPixel(output.getCorrectedColour(stripx), stripx);
          }
        }
      }
    }
  }
}


StripOutput getOutput(int stripIdx)
{
  for (StripOutput output : outputs)
  {
    if (output.strip == stripIdx) return output;
  }
  return null;
}

void oscEvent(OscMessage message)
{
  println("Rx'd message from ", message.address().substring(1, message.address().length()), message.port());
  NetAddress replyAddress = new NetAddress(message.address().substring(1, message.address().length()), message.port()+1);
  OscMessage reply = new OscMessage("/reply");
  if (message.checkAddrPattern("/status"))
  {

    reply.add("Devices " + outputs.size());
    int i = 0;
    for (DmxOutput output : dmxOutputs)
    {
      reply.add("Output " + i++);
      reply.add("Universe " + output.universe);
      reply.add("Subnet " + output.subnet);
      reply.add("Universe size " + output.universeSize);
      reply.add("Error " + output.error);
    }
  } else if (message.checkAddrPattern("/universe"))
  {
    if (message.checkTypetag("ii")) 
    {
      int output = message.get(0).intValue();
      if (output < outputs.size())
      {
        outputs.get(output).universe = message.get(1).intValue();
        reply.add("Set output " + output + " to universe " + outputs.get(output).universe);
      } else
      {
        reply.add("Error: not enough outputs. Connected DMX dongles: " + outputs.size() + ", attempted output: " + output);
      }
    } else reply.add("Error: wrong typetag. Expected two integers, got " + message.typetag());
  } else if (message.checkAddrPattern("/subnet"))
  {
    if (message.checkTypetag("ii")) 
    {
      int output = message.get(0).intValue();
      if (output < outputs.size())
      {
        outputs.get(output).subnet = message.get(1).intValue();
        reply.add("Set output " + output + " to subnet " + outputs.get(output).subnet);
      } else
      {
        reply.add("Error: not enough outputs. Connected DMX dongles: " + outputs.size() + ", attempted output: " + output);
      }
    } else reply.add("Error: wrong typetag. Expected two integers, got " + message.typetag());
  }
  osc.send(reply, replyAddress);
}
