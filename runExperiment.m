% ========================================================================
%> @brief runExperiment is the main Experiment object; Inherits from Handle
%>
%>RUNEXPERIMENT The main class which accepts a task and stimulus object
%>and runs the stimuli based on the task object passed. The class
%>controls the fundamental configuration of the screen (calibration, size
%>etc.), and manages communication to the DAQ system using TTL pulses out
%>and communication over a UDP client<->server socket.
%>  Stimulus must be a stimulus class, i.e. gratingStimulus and friends,
%>  so for example:
%>
%>  gs.g=gratingStimulus(struct('mask',1,'sf',1));
%>  ss=runExperiment(struct('stimulus',gs,'windowed',1));
%>  ss.run;
%>
%>	will run a minimal experiment showing a 1c/d circularly masked grating
% ========================================================================
classdef (Sealed) runExperiment < handle
	
	properties
		stimulus
		%> the stimulusSequence object(s) for the task
		task
		%> screen manager object
		screen
		%>show command logs and a time log after stimlus presentation
		verbose = false
		%> change the parameters for poorer temporal fidelity during debugging
		debug = false
		%> shows the info text and position grid during stimulus presentation
		visualDebug = true
		%> name of serial port to send TTL out on, if set to 'dummy' then ignore
		serialPortName = 'dummy'
		%> use LabJack for digital output?
		useLabJack = false
		%> LabJack object
		lJack
		%> gamma correction info saved as a calibrateLuminance object
		gammaTable
		%> this lets the UI leave commands
		uiCommand = ''
		%> log all frame times, gets slow for > 1e6 frames
		logFrames = true
	end
	
	properties (SetAccess = private, GetAccess = public)
		%> general computer info
		computer
		%> PTB info
		ptb
		%> gamma tables and the like
		screenVals
		%> log times during display
		timeLog
		%> for heterogenous stimuli, we need a way to index into the stimulus so
		%> we don't waste time doing this on each iteration
		sList
		%> info on the current run
		currentInfo
	end
	
	properties (SetAccess = private, GetAccess = private)
		%> properties allowed to be modified during construction
		allowedProperties='^(stimulus|task|screen|visualDebug|useLabJack|logFrames|serialPortName|debug|verbose)$'
		%> serial port object opened
		serialP
	end
	
	events
		runInfo
		abortRun
		endRun
	end
	
	%=======================================================================
	methods %------------------PUBLIC METHODS
		%=======================================================================
		
		% ===================================================================
		%> @brief Class constructor
		%>
		%> More detailed description of what the constructor does.
		%>
		%> @param args are passed as a structure of properties which is
		%> parsed.
		%> @return instance of the class.
		% ===================================================================
		function obj = runExperiment(args)
			if exist('args','var');obj.set(args);end
			obj.initialiseScreen;
		end
		
		% ===================================================================
		%> @brief The main run loop
		%>
		%> @param obj required class object
		% ===================================================================
		function run(obj)
			%initialise timeLog for this run
			obj.timeLog = timeLogger;
			%if obj.logFrames == false %preallocating these makes opticka drop frames when nFrames ~ 1e6
			%else
			%	obj.timeLog.vbl=zeros(obj.task.nFrames,1);
			%	obj.timeLog.show=zeros(obj.task.nFrames,1);
			%	obj.timeLog.flip=zeros(obj.task.nFrames,1);
			%	obj.timeLog.miss=zeros(obj.task.nFrames,1);
			%	obj.timeLog.stimTime=zeros(obj.task.nFrames,1);
			%end
			
			%make a handle to the screemManager
			s = obj.screen;
			%if s.windowed(1)==0 && obj.debug == false;HideCursor;end
			
			%-------Set up serial line and LabJack for this run...
			%obj.serialP=sendSerial(struct('name',obj.serialPortName,'openNow',1,'verbosity',obj.verbose));
			%obj.serialP.setDTR(0);
			
			if obj.useLabJack == true
				strct = struct('openNow',1,'name','default','verbosity',obj.verbose);
			else
				strct = struct('openNow',0,'name','null','verbosity',0,'silentMode',1);
			end
			obj.lJack = labJack(strct);
			%-----------------------------------------------------
			
			%---------This is our main TRY CATCH experiment display loop
			try
				
				obj.screenVals = s.initialiseScreen(obj.debug,obj.timeLog);
				
				%Trigger the omniplex (TTL on FIO1) into paused mode
				obj.lJack.setDIO([2,0,0]);WaitSecs(0.001);obj.lJack.setDIO([0,0,0]); 
				
				obj.initialiseTask; %set up our task structure for this run
				
				for j=1:obj.sList.n %parfor doesn't seem to help here...
					obj.stimulus{j}.setup(obj); %call setup and pass it the runExperiment object
				end
				
				obj.updateVars; %set the variables for the very first run;
				
				KbReleaseWait; %make sure keyboard keys are all released
				
				%bump our priority to maximum allowed
				Priority(MaxPriority(s.win)); 
				%--------------this is RSTART (Set HIGH FIO0->Pin 24), unpausing the omniplex
				if obj.useLabJack == true
					obj.lJack.setDIO([1,0,0],[1,0,0])
				end
				
				obj.task.tick = 1;
				obj.task.switched = 1;
				tL.screen.beforeDisplay = GetSecs;
				
				% lets draw 1 seonds worth of the stimuli we will be using
				% covered by a blank. this lets us prime the GPU with the sorts
				% of stimuli it will be using and this does appear to minimise
				% some of the frames lost on first presentation for very complex
				% stimuli using 32bit computation buffers...
				vbl = 0;
				for i = 1:s.screenVals.fps
					for j=1:obj.sList.n
						obj.stimulus{j}.draw();
					end
					s.drawBackground;
					s.drawFixationPoint;
					if s.photoDiode == true;s.drawPhotoDiodeSquare([0 0 0 1]);end
					Screen('DrawingFinished', s.win);
					vbl = Screen('Flip', s.win, vbl+0.001);
				end
				if obj.logFrames == true
					tL.screen.stimTime(1) = 1;
				end
				tL.vbl(1) = vbl;
				tL.startTime = tL.vbl(1);
				
				%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
				%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
				% Our main display loop
				%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
				%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
				while obj.task.thisTrial <= obj.task.nTrials
					if obj.task.isBlank == true
						if s.photoDiode == true
							s.drawPhotoDiodeSquare([0 0 0 1]);
						end
					else
						if ~isempty(s.backgroundColour)
							s.drawBackground;
						end
						for j=1:obj.sList.n
							obj.stimulus{j}.draw();
						end
						if s.photoDiode == true
							s.drawPhotoDiodeSquare([1 1 1 1]);
						end
						if s.fixationPoint == true
							s.drawFixationPoint;
						end
					end
					if s.visualDebug == true
						s.drawGrid;
						s.infoText;
					end
					
					Screen('DrawingFinished', s.win); % Tell PTB that no further drawing commands will follow before Screen('Flip')
					
					[~, ~, buttons]=GetMouse(s.screen);
					if buttons(2)==1;notify(obj,'abortRun');break;end; %break on any mouse click, needs to change
					if strcmp(obj.uiCommand,'stop');break;end
					%if KbCheck;notify(obj,'abortRun');break;end;
						
					obj.updateTask(); %update our task structure
					
					%======= FLIP: Show it at correct retrace: ========%
					nextvbl = tL.vbl(end) + obj.screenVals.halfisi;
					if obj.logFrames == true
						[tL.vbl(obj.task.tick),tL.show(obj.task.tick),tL.flip(obj.task.tick),tL.miss(obj.task.tick)] = Screen('Flip', s.win, nextvbl);
					else
						tL.vbl = Screen('Flip', s.win, nextvbl);
					end
					%==================================================%
					if obj.task.strobeThisFrame == true
						obj.lJack.strobeWord; %send our word out to the LabJack
					end
					
					if obj.task.tick == 1
						tL.startTime=tL.vbl(1); %respecify this with actual stimulus vbl
					end
					
					if obj.logFrames == true
						if obj.task.isBlank == false
							tL.stimTime(obj.task.tick)=1+obj.task.switched;
						else
							tL.stimTime(obj.task.tick)=0-obj.task.switched;
						end
					end
					
					if (s.movieSettings.loop <= s.movieSettings.nFrames) && obj.task.isBlank == false
						s.addMovieFrame();
					end
					
					obj.task.tick=obj.task.tick+1;
					
				end
				
				%---------------------------------------------Finished display loop
				obj.drawBackground;
				vbl=Screen('Flip', s.win);
				%obj.lJack.prepareStrobe(2047,[],1);
				tL.screen.afterDisplay=vbl;
				obj.lJack.setDIO([0,0,0],[1,0,0]); %this is RSTOP, pausing the omniplex
				notify(obj,'endRun');
				
				tL.screen.deltaDispay=tL.screen.afterDisplay - tL.screen.beforeDisplay;
				tL.screen.deltaUntilDisplay=tL.screen.startTime - tL.screen.beforeDisplay;
				tL.screen.deltaToFirstVBL=tL.vbl(1) - tL.screen.beforeDisplay;
				
				obj.info = Screen('GetWindowInfo', s.win);
				
				s.resetScreenGamma();
				
				s.finaliseMovie(false);
				
				s.closeScreen();
				
				obj.lJack.setDIO([2,0,0]);WaitSecs(0.05);obj.lJack.setDIO([0,0,0]); %we stop recording mode completely
				obj.lJack.close;
				obj.lJack=[];
				
				s.playMovie();
				
			catch ME
				
				obj.lJack.setDIO([0,0,0]);
				
				s.resetScreenGamma();
				
				s.finaliseMovie(true);
				
				s.closeScreen();
				
				%obj.serialP.close;
				obj.lJack.close;
				obj.lJack=[];
				rethrow(ME)
				
			end
			
			if obj.verbose==1
				tL.printLog;
			end
		end
		
		% ===================================================================
		%> @brief prepare the Screen values on the local machine
		%>
		%> @param
		%> @return
		% ===================================================================
		function initialiseScreen(obj)
			
			obj.timeLog = timeLogger;
			obj.screen = screenManager;
			
			obj.screen.movieSettings.record = 0;
			obj.screen.movieSettings.size = [400 400];
			obj.screen.movieSettings.quality = 0;
			obj.screen.movieSettings.nFrames = 100;
			obj.screen.movieSettings.type = 1;
			obj.screen.movieSettings.codec = 'rle ';
			
			obj.lJack = labJack(struct('name','labJack','openNow',1,'verbosity',1));
			obj.lJack.prepareStrobe(0,[0,255,255],1);
			obj.lJack.close;
			obj.lJack=[];
			
			obj.computer=Screen('computer');
			obj.ptb=Screen('version');
			
			obj.updatesList;

			a=zeros(20,1);
			for i=1:20
				a(i)=GetSecs;
			end
			obj.timeLog.screen.deltaGetSecs=mean(diff(a))*1000; %what overhead does GetSecs have in milliseconds?
			WaitSecs(0.01); %preload function
			
			obj.screenVals = obj.screen.prepareScreen;
			
			obj.timeLog.screen.prepTime=GetSecs-obj.timeLog.screen.construct;
			
		end
		
		
		% ===================================================================
		%> @brief getTimeLog Prints out the frame time plots from a run
		%>
		%> @param
		% ===================================================================
		function getTimeLog(obj)
			obj.timeLog.printLog;
		end
		
		% ===================================================================
		%> @brief getTimeLog Prints out the frame time plots from a run
		%>
		%> @param
		% ===================================================================
		function deleteTimeLog(obj)
			%obj.timeLog = [];
		end
		
		% ===================================================================
		%> @brief getTimeLog Prints out the frame time plots from a run
		%>
		%> @param
		% ===================================================================
		function restoreTimeLog(obj,tLog)
			if isstruct(tLog);obj.timeLog = tLog;end
		end
		
		% ===================================================================
		%> @brief refresh the screen values stored in the object
		%>
		%> @param
		% ===================================================================
		function refreshScreen(obj)
			obj.screenVals = obj.screen.prepareScreen();
		end
		
		% ===================================================================
		%> @brief updatesList
		%> Updates the list of stimuli current in the object
		%> @param
		% ===================================================================
		function updatesList(obj)
			if isempty(obj.stimulus) || isstruct(obj.stimulus{1}) %stimuli should be class not structure, reset
				obj.stimulus = [];
			end
			obj.sList.n = 0;
			obj.sList.list = [];
			obj.sList.index = [];
			obj.sList.gN = 0;
			obj.sList.bN = 0;
			obj.sList.dN = 0;
			obj.sList.sN = 0;
			obj.sList.uN = 0;
			if ~isempty(obj.stimulus)
				sn=length(obj.stimulus);
				obj.sList.n=sn;
				for i=1:sn
					obj.sList.index = [obj.sList.index i];
					switch obj.stimulus{i}.family
						case 'grating'
							obj.sList.list = [obj.sList.list 'g'];
							obj.sList.gN = obj.sList.gN + 1;
						case 'bar'
							obj.sList.list = [obj.sList.list 'b'];
							obj.sList.bN = obj.sList.bN + 1;
						case 'dots'
							obj.sList.list = [obj.sList.list 'd'];
							obj.sList.dN = obj.sList.dN + 1;
						case 'spot'
							obj.sList.list = [obj.sList.list 's'];
							obj.sList.sN = obj.sList.sN + 1;
						otherwise
							obj.sList.list = [obj.sList.list 'u'];
							obj.sList.uN = obj.sList.uN + 1;
					end
				end
			end
		end
		
	end%-------------------------END PUBLIC METHODS--------------------------------%
	
	%=======================================================================
	methods (Access = private) %------------------PRIVATE METHODS
		%=======================================================================
		
		% ===================================================================
		%> @brief InitialiseTask
		%> Sets up the task structure with dynamic properties
		%> @param
		% ===================================================================
		function initialiseTask(obj)
			
			if isempty(obj.task) %we have no task setup, so we generate one.
				obj.task=stimulusSequence;
				obj.task.nTrials=1;
				obj.task.nSegments = 1;
				obj.task.trialTime = 2;
				obj.task.randomiseStimuli;
			end
			%find out how many stimuli there are, wrapped in the obj.stimulus
			%structure
			obj.updatesList;
			
			%Set up the task structures needed
			
			if isempty(obj.task.findprop('tick'))
				obj.task.addprop('tick'); %add new dynamic property
			end
			obj.task.tick=0;
			
			if isempty(obj.task.findprop('blankTick'))
				obj.task.addprop('blankTick'); %add new dynamic property
			end
			obj.task.blankTick=0;
			
			if isempty(obj.task.findprop('thisRun'))
				obj.task.addprop('thisRun'); %add new dynamic property
			end
			obj.task.thisRun=1;
			
			if isempty(obj.task.findprop('thisTrial'))
				obj.task.addprop('thisTrial'); %add new dynamic property
			end
			obj.task.thisTrial=1;
			
			if isempty(obj.task.findprop('totalRuns'))
				obj.task.addprop('totalRuns'); %add new dynamic property
			end
			obj.task.totalRuns=1;
			
			if isempty(obj.task.findprop('isBlank'))
				obj.task.addprop('isBlank'); %add new dynamic property
			end
			obj.task.isBlank = false;
			
			if isempty(obj.task.findprop('switched'))
				obj.task.addprop('switched'); %add new dynamic property
			end
			obj.task.switched = false;
			
			if isempty(obj.task.findprop('strobeThisFrame'))
				obj.task.addprop('strobeThisFrame'); %add new dynamic property
			end
			obj.task.strobeThisFrame = false;
			
			if isempty(obj.task.findprop('doUpdate'))
				obj.task.addprop('doUpdate'); %add new dynamic property
			end
			obj.task.doUpdate = false;
			
			if isempty(obj.task.findprop('startTime'))
				obj.task.addprop('startTime'); %add new dynamic property
			end
			obj.task.startTime=0;
			
			if isempty(obj.task.findprop('switchTime'))
				obj.task.addprop('switchTime'); %add new dynamic property
			end
			obj.task.switchTime=0;
			
			if isempty(obj.task.findprop('switchTick'))
				obj.task.addprop('switchTick'); %add new dynamic property
			end
			obj.task.switchTick=0;
			
			if isempty(obj.task.findprop('timeNow'))
				obj.task.addprop('timeNow'); %add new dynamic property
			end
			obj.task.timeNow=0;
			
			if isempty(obj.task.findprop('stimIsDrifting'))
				obj.task.addprop('stimIsDrifting'); %add new dynamic property
			end
			obj.task.stimIsDrifting=[];
			
			if isempty(obj.task.findprop('stimIsMoving'))
				obj.task.addprop('stimIsMoving'); %add new dynamic property
			end
			obj.task.stimIsMoving=[];
			
			if isempty(obj.task.findprop('stimIsDots'))
				obj.task.addprop('stimIsDots'); %add new dynamic property
			end
			obj.task.stimIsDots=[];
			
			if isempty(obj.task.findprop('stimIsFlashing'))
				obj.task.addprop('stimIsFlashing'); %add new dynamic property
			end
			obj.task.stimIsFlashing=[];
			
		end
		
		% ===================================================================
		%> @brief updateVars
		%> Updates the stimulus objects with the current variable set
		%> @param thisTrial is the current trial
		%> @param thisRun is the current run
		% ===================================================================
		function updateVars(obj,thisTrial,thisRun)
			
			%As we change variables in the blank, we optionally send the
			%values for the next stimulus
			if ~exist('thisTrial','var') || ~exist('thisRun','var')
				thisTrial=obj.task.thisTrial;
				thisRun=obj.task.thisRun;
			end
			
			if thisTrial > obj.task.nTrials
				return %we've reached the end of the experiment, no need to update anything!
			end
			
			%start looping through out variables
			for i=1:obj.task.nVars
				ix = obj.task.nVar(i).stimulus; %which stimulus
				value=obj.task.outVars{thisTrial,i}(thisRun);
				name=[obj.task.nVar(i).name 'Out']; %which parameter
				offsetix = obj.task.nVar(i).offsetstimulus;
				offsetvalue = obj.task.nVar(i).offsetvalue;
				
				if ~isempty(offsetix)
					obj.stimulus{offsetix}.(name)=value+offsetvalue;
					if thisTrial ==1 && thisRun == 1 %make sure we update if this is the first run, otherwise the variables may not update properly
						obj.stimulus{offsetix}.update;
					end
				end
				
				if obj.task.blankTick > 2 && obj.task.blankTick <= obj.sList.n + 2
% 						obj.stimulus{j}.(name)=value;
				else
					for j = ix %loop through our stimuli references for this variable
						if obj.verbose==true;tic;end
						obj.stimulus{j}.(name)=value;
						if thisTrial == 1 && thisRun == 1 %make sure we update if this is the first run, otherwise the variables may not update properly
							obj.stimulus{j}.update;
						end
						if obj.verbose==true;fprintf('\nVariable assign %i: %g seconds',j,toc);end
					end
				end
			end
		end
		
		% ===================================================================
		%> @brief updateTask
		%> Updates the stimulus run state; update the stimulus values for the
		%> current trial and increments the switchTime and switchTick timer
		% ===================================================================
		function updateTask(obj)
			obj.task.timeNow = GetSecs;
			if obj.task.tick==1 %first frame
				obj.task.isBlank = false;
				obj.task.startTime = obj.task.timeNow;
				obj.task.switchTime = obj.task.trialTime; %first ever time is for the first trial
				obj.task.switchTick = obj.task.trialTime*ceil(obj.screenVals.fps);
				obj.lJack.prepareStrobe(obj.task.outIndex(obj.task.totalRuns));
				obj.task.strobeThisFrame = true;
			end
			
			%-------------------------------------------------------------------
			if obj.task.realTime == true %we measure real time
				trigger = obj.task.timeNow <= (obj.task.startTime+obj.task.switchTime);
			else %we measure frames, prone to error build-up
				trigger = obj.task.tick < obj.task.switchTick;
			end
			
			if trigger == true

				if obj.task.isBlank == false %showing stimulus, need to call animate for each stimulus
					% because the update happens before the flip, but the drawing of the update happens
					% only in the next loop, we have to send the strobe one loop after we set switched
					% to true
					if obj.task.switched == true; 
						obj.task.strobeThisFrame = true;
					else
						obj.task.strobeThisFrame = false;
					end
					
					%if obj.verbose==true;tic;end
					for i = 1:obj.sList.n %parfor appears faster here for 6 stimuli at least
						obj.stimulus{i}.animate;
					end
					%if obj.verbose==true;fprintf('\nStimuli animation: %g seconds',toc);end
					
				else %this is a blank stimulus
					obj.task.blankTick = obj.task.blankTick + 1;
					%this causes the update of the stimuli, which may take more than one refresh, to
					%occur during the second blank flip, thus we don't lose any timing.
					if obj.task.switched == false && obj.task.strobeThisFrame == true
						obj.task.doUpdate = true;
					end
					% because the update happens before the flip, but the drawing of the update happens
					% only in the next loop, we have to send the strobe one loop after we set switched
					% to true
					if obj.task.switched == true; 
						obj.task.strobeThisFrame = true;
					else
						obj.task.strobeThisFrame = false;
					end
					% now update our stimuli, we do it after the first blank as less
					% critical timingwise
					if obj.task.doUpdate == true
						if ~mod(obj.task.thisRun,obj.task.minTrials) %are we rolling over into a new trial?
							mT=obj.task.thisTrial+1;
							mR = 1;
						else
							mT=obj.task.thisTrial;
							mR = obj.task.thisRun + 1;
						end
						%obj.uiCommand;
						if obj.verbose==true;tic;end
						obj.updateVars(mT,mR);
% 						for i = 1:obj.sList.n
% 							obj.stimulus{i}.update;
% 						end
								obj.task.doUpdate = false;
									if obj.verbose==true;fprintf('\nVariable update: %g seconds',toc);end
					end
					
					%this dispatches each stimulus update on a new blank frame to
					%reduce overhead.
					if obj.task.blankTick > 2 && obj.task.blankTick <= obj.sList.n + 2
						if obj.verbose==true;tic;end
						obj.stimulus{obj.task.blankTick-2}.update;
						if obj.verbose==true;fprintf('\nStimuli update: %g seconds',toc);end
					end
					
				end
				obj.task.switched = false;
				
				%-------------------------------------------------------------------
			else %need to switch to next trial or blank
				obj.task.switched = true;
				if obj.task.isBlank == false %we come from showing a stimulus
					%obj.logMe('IntoBlank');
					obj.task.isBlank = true;
					obj.task.blankTick = 0;
					
					if ~mod(obj.task.thisRun,obj.task.minTrials) %are we within a trial block or not? we add the required time to our switch timer
						obj.task.switchTime=obj.task.switchTime+obj.task.itTime;
						obj.task.switchTick=obj.task.switchTick+(obj.task.itTime*ceil(obj.screenVals.fps));
					else
						obj.task.switchTime=obj.task.switchTime+obj.task.isTime;
						obj.task.switchTick=obj.task.switchTick+(obj.task.isTime*ceil(obj.screenVals.fps));
					end
					
					obj.lJack.prepareStrobe(2047); %get the strobe word to signify stimulus OFF ready
					%obj.logMe('OutaBlank');
					
				else %we have to show the new run on the next flip
					
					%obj.logMe('IntoTrial');
					if obj.task.thisTrial <= obj.task.nTrials
						obj.task.switchTime=obj.task.switchTime+obj.task.trialTime; %update our timer
						obj.task.switchTick=obj.task.switchTick+(obj.task.trialTime*round(obj.screenVals.fps)); %update our timer
						obj.task.isBlank = false;
						obj.task.totalRuns = obj.task.totalRuns + 1;
						if ~mod(obj.task.thisRun,obj.task.minTrials) %are we rolling over into a new trial?
							obj.task.thisTrial=obj.task.thisTrial+1;
							obj.task.thisRun = 1;
						else
							obj.task.thisRun = obj.task.thisRun + 1;
						end
						if obj.task.totalRuns <= length(obj.task.outIndex)
							obj.lJack.prepareStrobe(obj.task.outIndex(obj.task.totalRuns)); %get the strobe word ready
						else
							
						end
					else
						obj.task.thisTrial = obj.task.nTrials + 1;
					end
					%obj.logMe('OutaTrial');
					
				end
			end
		end
		
		% ===================================================================
		%> @brief Prints messages dependent on verbosity
		%>
		%> Prints messages dependent on verbosity
		%> @param in the calling function
		%> @param message the message that needs printing to command window
		% ===================================================================
		function salutation(obj,in,message)
			if obj.verbose==true
				if ~exist('in','var')
					in = 'undefined';
				end
				if exist('message','var')
					fprintf(['>>>runExperiment: ' message ' | ' in '\n']);
				else
					fprintf(['>>>runExperiment: ' in '\n']);
				end
			end
		end
		
		% ===================================================================
		%> @brief Logs the run loop parameters along with a calling tag
		%>
		%> Logs the run loop parameters along with a calling tag
		%> @param tag the calling function
		% ===================================================================
		function logMe(obj,tag)
			if obj.verbose == 1 && obj.debug == 1
				if ~exist('tag','var')
					tag='#';
				end
				fprintf('%s -- T: %i | R: %i [%i] | B: %i | Tick: %i | Time: %5.8g\n',tag,obj.task.thisTrial,obj.task.thisRun,obj.task.totalRuns,obj.task.isBlank,obj.task.tick,obj.task.timeNow-obj.task.startTime);
			end
		end
		
		% ===================================================================
		%> @brief Sets properties from a structure, ignores invalid properties
		%>
		%> @param args input structure
		% ===================================================================
		function set(obj,args)
			while iscell(args) && length(args) == 1
				args = args{1};
			end
			if iscell(args)
				if mod(length(args),2) == 1 % odd
					args = args(1:end-1); %remove last arg
				end
				odd = logical(mod(1:length(args),2));
				even = logical(abs(odd-1));
				args = cell2struct(args(even),args(odd),2);
			end
			fnames = fieldnames(args); %find our argument names
			for i=1:length(fnames);
				if regexp(fnames{i},obj.allowedPropertiesBase) %only set if allowed property
					obj.salutation(fnames{i},'Configuring setting');
					obj.(fnames{i})=args.(fnames{i}); %we set up the properies from the arguments as a structure
				end
			end
		end
		
	end
	
	methods (Static)
		function lobj=loadobj(in)
			fprintf('Loading runExperiment object...\n');	
			lobj = in;
		end
	end
	
end