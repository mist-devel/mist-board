APP=ESCParser
SRC=Drivers.cpp ESCParser.cpp Interpreter.cpp  RobotronFont.cpp
EXAMPLE=screenshot

$(APP): $(SRC)

test: $(APP)
	./$(APP) -svg $(EXAMPLE).esc > $(EXAMPLE).svg
	convert $(EXAMPLE).svg $(EXAMPLE).gif
	display $(EXAMPLE).gif
