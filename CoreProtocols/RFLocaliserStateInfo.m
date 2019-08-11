%=====RF Localiser state configuration file=====
%------------General Settings-----------------
tS.rewardTime           = 150; %==TTL time in milliseconds
tS.rewardPin            = 2; %==Output pin, 2 by default with Arduino.
tS.useTask = false; %use stimulusSequence (randomised variable task object)
tS.checkKeysDuringStimulus = true; %==allow keyboard control? Slight drop in performance
tS.recordEyePosition = false; %==record eye position within PTB, **in addition** to the EDF?
tS.askForComments = false; %==little UI requestor asks for comments before/after run
tS.saveData = false; %we don't want to save any data
tS.dummyEyelink = false; %==use mouse as a dummy eyelink, good for testing away from the lab.
tS.useMagStim = false; %enable the magstim manager
tS.name = 'RF Localiser'; %==name of this protocol
me.useEyeLink = true;
me.useArduino = true;
rM.verbose = true;

%-----enable the magstimManager which uses FOI1 of the LabJack
if tS.useMagStim
	mS = magstimManager('lJ',lJ,'defaultTTL',2);
	mS.stimulateTime	= 240;
	mS.frequency		= 0.7;
	mS.rewardTime		= 25;
	open(mS);
end

%------------Eyelink Settings----------------
eL.isDummy = false; %use dummy or real eyelink?
tS.fixX = 0;
tS.fixY = 0;
tS.firstFixInit = 0.75;
tS.firstFixTime = 1.5;
tS.firstFixRadius = 4;

% X, Y, FixInitTime, FixTime, Radius, StrictFix
eL.updateFixationValues(tS.fixX, tS.fixY, tS.firstFixInit, tS.firstFixTime, tS.firstFixRadius, true);
if tS.saveData == true; eL.recordData = true; end %===save EDF file?
if tS.dummyEyelink; eL.isDummy = true; end %===use dummy or real eyelink? 
eL.sampleRate = 250;
eL.remoteCalibration = true; %manual calibration
eL.calibrationStyle = 'HV5'; % calibration style
eL.modify.calibrationtargetcolour = [1 1 1];
eL.modify.calibrationtargetsize = 2;
eL.modify.calibrationtargetwidth = 0.01;
eL.modify.waitformodereadytime = 500;
eL.modify.devicenumber = -1; % -1==use any keyboard

%-------randomise stimulus variables every trial?
% me.stimuli.choice = [];
% n = 1;
% in(n).name = 'xyPosition';
% in(n).values = [6 6; 6 -6; -6 6; -6 -6; -6 0; 6 0];
% in(n).stimuli = [7 8];
% in(n).offset = [];
% me.stimuli.stimulusTable = in;
me.stimuli.choice = [];
me.stimuli.stimulusTable = [];

%--------allows using arrow keys to control this table during presentation
me.stimuli.tableChoice = 1;
n=1;
me.stimuli.controlTable(n).variable = 'angle';
me.stimuli.controlTable(n).delta = 15;
me.stimuli.controlTable(n).stimuli = [6 7 8 9 10];
me.stimuli.controlTable(n).limits = [0 360];
n=n+1;
me.stimuli.controlTable(n).variable = 'size';
me.stimuli.controlTable(n).delta = 0.25;
me.stimuli.controlTable(n).stimuli = [2 3 4 5 6 7 8 10];
me.stimuli.controlTable(n).limits = [0.25 20];
n=n+1;
me.stimuli.controlTable(n).variable = 'flashTime';
me.stimuli.controlTable(n).delta = 0.1;
me.stimuli.controlTable(n).stimuli = [1 2 3 4 5 6];
me.stimuli.controlTable(n).limits = [0.1 1];
n=n+1;
me.stimuli.controlTable(n).variable = 'barLength';
me.stimuli.controlTable(n).delta = 1;
me.stimuli.controlTable(n).stimuli = [9];
me.stimuli.controlTable(n).limits = [0.5 15];
n=n+1;
me.stimuli.controlTable(n).variable = 'barWidth';
me.stimuli.controlTable(n).delta = 0.25;
me.stimuli.controlTable(n).stimuli = [9];
me.stimuli.controlTable(n).limits = [0.25 8.25];
n=n+1;
me.stimuli.controlTable(n).variable = 'tf';
me.stimuli.controlTable(n).delta = 0.1;
me.stimuli.controlTable(n).stimuli = [7 8];
me.stimuli.controlTable(n).limits = [0 12];
n=n+1;
me.stimuli.controlTable(n).variable = 'sf';
me.stimuli.controlTable(n).delta = 0.1;
me.stimuli.controlTable(n).stimuli = [7 8];
me.stimuli.controlTable(n).limits = [0.1 8];
n=n+1;
me.stimuli.controlTable(n).variable = 'speed';
me.stimuli.controlTable(n).delta = 0.5;
me.stimuli.controlTable(n).stimuli = [10];
me.stimuli.controlTable(n).limits = [0.5 8.5];
n=n+1;
me.stimuli.controlTable(n).variable = 'density';
me.stimuli.controlTable(n).delta = 5;
me.stimuli.controlTable(n).stimuli = [10];
me.stimuli.controlTable(n).limits = [1 151];
n=n+1;
me.stimuli.controlTable(n).variable = 'dotSize';
me.stimuli.controlTable(n).delta = 0.01;
me.stimuli.controlTable(n).stimuli = [10];
me.stimuli.controlTable(n).limits = [0.04 0.51];

%------this allows us to enable subsets from our stimulus list
me.stimuli.stimulusSets = {[11], [2 11], [3 11], [4 11], [5 11], [6 11], [7 11], [8 11], [9 11], [10 11]};
me.stimuli.setChoice = 1;
showSet(me.stimuli);

%-------------------State Machine Control Functions------------------
% these are our functions that will execute as the stateMachine runs,
% in the scope of the runExperiemnt object.
% io = datapixx (digital I/O to plexon)
% s = screenManager
% sM = State Machine
% eL = eyelink manager
% lJ = LabJack (reward trigger to Crist reward system)
% bR = behavioural record plot
%--------------------------------------------------------------------
%pause entry
pauseEntryFcn = {
	@()setOffline(eL); 
	@()fprintf('\n===>>>ENTER PAUSE STATE\n');
};

%prestim entry
psEntryFcn = { 
	@()setOffline(eL); ...
	@()randomise(me.stimuli); ...
	@()getStimulusPositions(me.stimuli); ... %make a struct the eL can use for drawing stim positions
	@()trackerClearScreen(eL); ... 
	@()trackerDrawFixation(eL); ...
	@()trackerDrawStimuli(eL,me.stimuli.stimulusPositions); ... %draw location of stimulus on eyelink
	@()resetFixation(eL); ...
	@()startRecording(eL); ...
	};

%prestimulus blank
prestimulusFcn = { 
	@()drawBackground(s); ...
};

%exiting prestimulus state
psExitFcn = { 
	@()update(me.stimuli); ...
	@()show(me.stimuli{11}); ...
	@()statusMessage(eL,'Showing Fixation Spot...'); ...
};

%what to run when we enter the stim presentation state
stimEntryFcn = {};

%what to run when we are showing stimuli
stimFcn = { 
	@()draw(me.stimuli); ...	@()drawEyePosition(eL); ...
	@()finishDrawing(s); ...
	@()animate(me.stimuli); ... % animate stimuli for subsequent draw
};

%test we are maintaining fixation
maintainFixFcn = {
	@()testSearchHoldFixation(eL,'correct','breakfix');
};

%as we exit stim presentation state
stimExitFcn = {
	@()mousePosition(s,true);
	};

%if the subject is correct (small reward)
correctEntryFcn = { 
	@()timedTTL(rM,tS.rewardPin,tS.rewardTime); ... % labjack sends a TTL to Crist reward system
	@()drawTimedSpot(s, 0.5, [0 1 0 1]); ...
	@()statusMessage(eL,'Correct! :-)'); ...
	@()stopRecording(eL); ...
	};

%correct stimulus
correctFcn = { 
	@()drawTimedSpot(s, 0.5, [0 1 0 1]); 
};

%when we exit the correct state
ExitFcn = { 
	@()updatePlot(bR, eL, sM); ...
	@()drawTimedSpot(s, 0.5, [0 1 0 1], 0.2, true); ... %reset the timer on the green spot
};

%break entry
breakEntryFcn = { 
	@()statusMessage(eL,'Broke Fixation :-('); ...
	@()stopRecording(eL); ...
};

%incorrect entry
incorrEntryFcn = { 
	@()statusMessage(eL,'Incorrect :-('); ...
	@()stopRecording(eL); ...
};

%our incorrect stimulus
breakFcn =  {@()drawBackground(s);};

%calibration function
calibrateFcn = {@()trackerSetup(eL);};

%flash function
flashFcn = {@()flashScreen(s,0.2);};

% allow override
overrideFcn = {@()keyOverride(me,tS);};

%show 1deg size grid
gridFcn = {@()drawGrid(s);};

%----------------------State Machine Table-------------------------
disp('================>> Building state info file <<================')
%specify our cell array that is read by the stateMachine
stateInfoTmp = { ...
'name'      'next'			'time'  'entryFcn'		'withinFcn'		'transitionFcn'	'exitFcn'; ...
'pause'		'blank'			inf 	pauseEntryFcn	[]				[]				[]; ...
'blank'		'stimulus'		0.5	psEntryFcn		prestimulusFcn	[]			psExitFcn; ...
'stimulus'  'incorrect'		3		stimEntryFcn	stimFcn			maintainFixFcn	stimExitFcn; ...
'incorrect'	'blank'			1		incorrEntryFcn	breakFcn		[]				ExitFcn; ...
'breakfix'	'blank'			1		breakEntryFcn	breakFcn		[]				ExitFcn; ...
'correct'	'blank'			0.5	correctEntryFcn	correctFcn		[]		ExitFcn; ...
'calibrate' 'pause'			0.5	calibrateFcn	[]				[]				[]; ...
'flash'		'pause'			0.5	[]					flashFcn		[]				[]; ...
'override'	'pause'			0.5	[]					overrideFcn		[]			[]; ...
'showgrid'	'pause'			1		[]					gridFcn			[]			[]; ...
};
disp(stateInfoTmp)
disp('================>> Building state info file <<================')
clear maintainFixFcn prestimulusFcn singleStimulus ...
	prestimulusFcn stimFcn stimEntryFcn stimExitfcn correctEntry correctWithin correctExit ...
	incorrectFcn calibrateFcn gridFcn overrideFcn flashFcn breakFcn
