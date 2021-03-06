%SALIENCE state configuration file, this gets loaded by opticka via
%runExperiment class. The following class objects are loaded and available to
%use: 
% me = runExperiment object
% io = digital I/O to recording system
% s  = PTB screenManager
% sM = State Machine
% eL = eyetracker manager
% t  = task sequence (stimulusSequence class)
% rM = Reward Manager (LabJack or Arduino TTL trigger to Crist reward system/Magstim)
% bR = behavioural record plot (on screen GUI during task run)
% me.stimuli = our list of stimuli
% tS = general struct to hold variables for this run

%------------General Settings-----------------
tS.useTask              = true; %==use stimulusSequence (randomised variable task object)
tS.rewardTime           = 300; %==TTL time in milliseconds
tS.rewardPin            = 2; %==Output pin, 2 by default with Arduino.
tS.checkKeysDuringStimulus = false; %==allow keyboard control? Slight drop in performance
tS.recordEyePosition	= false; %==record eye position within PTB, **in addition** to the EDF?
tS.askForComments		= false; %==little UI requestor asks for comments before/after run
tS.saveData				= true; %==save behavioural and eye movement data?
tS.dummyEyelink         = false; %==use mouse as a dummy eyelink, good for testing away from the lab.
tS.name					= 'salience-task'; %==name of this protocol
%io.verbose				= true; %==show the triggers sent in the command window
%eL.verbose				= true;
bR.correctStateName		= 'post';
me.useEyeLink           = true;
me.useArduino           = true;
				
%------------Eyetracker Settings-----------------
tS.fixX				= 0;
tS.fixY				= 0;
tS.firstFixInit		= 1;
tS.firstFixTime		= 0.4;
tS.firstFixRadius	= 3;
tS.keepFixInit		= 0;
tS.keepFixTime		= 0.6;
tS.strict			= true; %do we allow (strict==false) multiple entry/exits of fix window within the time limit
me.lastXPosition	= tS.fixX;
me.lastYPosition	= tS.fixY;

%------------------------Eyelink setup--------------------------
eL.name = tS.name;
if tS.saveData == true; eL.recordData = true; end %===save EDF file?
if tS.dummyEyelink; eL.isDummy = true; end %===use dummy or real eyelink? 
eL.sampleRate = 1000;
eL.calibrationStyle = 'HV5'; %===5 point calibration
%===========================
% remote calibration enables manual control and selection of each fixation
% this is useful for a baby or monkey who has not been trained for fixation
% use 1-9 to show each dot, space to select fix as valid, INS key ON EYELINK KEYBOARD to
% accept calibration!
eL.remoteCalibration = true; 
%===========================
eL.modify.calibrationtargetcolour = [1 1 1];
eL.modify.calibrationtargetsize = 2;
eL.modify.calibrationtargetwidth = 0;
eL.modify.waitformodereadytime = 500;
eL.modify.targetbeep = 1;
eL.modify.devicenumber = -1; % -1 = use any keyboard

%Initialise the eyeLink object with X, Y, FixInitTime, FixTime, Radius, StrictFix
eL.updateFixationValues(tS.fixX, tS.fixY, tS.firstFixInit, tS.firstFixTime, tS.firstFixRadius, tS.strict);

%randomise stimulus variables every trial? useful during initial training but not for
%data collection.
me.stimuli.choice = [];
me.stimuli.stimulusTable = [];

% allows using arrow keys to control this table during the main loop
% ideal for mapping receptive fields so we can twiddle parameters, normally not used
% for normal tasks
me.stimuli.controlTable = [];
me.stimuli.tableChoice = 1;

% this allows us to enable subsets from our stimulus list. So each set is a
% particular display like fixation spot only, background. During the trial you can
% use the showSet method of me.stimuli to change to a particular stimulus set.
me.stimuli.stimulusSets = {[3],[1 2 3],[1 2]};
me.stimuli.setChoice = 1;
showSet(me.stimuli);

%which stimulus in the list is used for a fixation target? 
me.stimuli.fixationChoice = 3;

%----------------------State Machine States-------------------------
% these are our functions that will execute as the stateMachine runs,
% in the scope of the runExperiemnt object.
% each "function" is a cell array of anonymous function handles that enables
% each state to perform a set of actions on entry, during and on exit of that state.

%--------------------pause entry
pauseEntryFcn = {
	@()hide(me.stimuli); ...
	@()drawBackground(s); ... %blank the display
	%@()pauseRecording(io); ...
	@()drawTextNow(s,'Paused, press [p] to resume...'); ...
	@()disp('Paused, press [p] to resume...'); ...
	@()trackerClearScreen(eL); ... 
	@()trackerDrawText(eL,'PAUSED, press [P] to resume...'); ...
	@()edfMessage(eL,'TRIAL_RESULT -100'); ... %store message in EDF
	@()stopRecording(eL); ... %stop eye position recording
	@()disableFlip(me); ... %stop screen updates
	@()needEyeSample(me,false); ...
}; 

%--------------------pause exit
pauseExitFcn = { 
	@()enableFlip(me); ...
	@()needEyeSample(me,true); ...
	%@()resumeRecording(io); ...
};

%--------------------prefixate entry
prefixEntryFcn = { 
	@()setOffline(eL); ... %make sure offline before start recording
	@()resetFixation(eL); ... %reset the fixation counters ready for a new trial
	@()updateFixationValues(eL,tS.fixX,tS.fixY,tS.firstFixInit,tS.firstFixTime,tS.firstFixRadius); %reset 
	@()hide(me.stimuli); ...
	@()trackerClearScreen(eL); ...
	@()statusMessage(eL,'Prefixation...'); ... %status text on the eyelink
	@()logRun(me,'PREFIX'); ... %fprintf current trial info
};

%--------------------prefixate
prefixFcn = {  };

%--------------------prefixate exit
prefixExitFcn = {
	@()edfMessage(eL,'V_RT MESSAGE END_FIX END_RT'); ...
	@()edfMessage(eL,sprintf('TRIALID %i',getTaskIndex(me))); ...
	@()edfMessage(eL,['UUID ' UUID(sM)]); ... %add in the uuid of the current state for good measure
	@()edfMessage(eL,'MSG:Hello there! '); ... 
	@()startRecording(eL); ... %start eyelink recording eye data
	@()statusMessage(eL,'Get Fixation...'); ... %status text on the eyelink
	@()trackerDrawFixation(eL); ... 
	@()needEyeSample(me,true); ...
	@()changeSet(me.stimuli,1); ...
};

%--------------------------------
%--------------------fixate entry
fixEntryFcn = { 
	@()startFixation(io);
};

%--------------------fix within
fixFcn = { 
	@()draw(me.stimuli); 
};

%--------------------test we are fixated for a certain length of time
initFixFcn = { 
	@()testSearchHoldFixation(eL,'stimfix','incorrect'); 
};

%--------------------exit fixation phase
fixExitFcn = { 
	@()updateFixationValues(eL,[],[],tS.keepFixInit,tS.keepFixTime); %reset
	@()changeSet(me.stimuli,2); ...
	@()trackerClearScreen(eL); ...
	@()getStimulusPositions(me.stimuli); ... %make a struct the eL can use for drawing stim positions
	@()trackerDrawStimuli(eL,me.stimuli.stimulusPositions); ... %draw location of stimulus on eyelink
};

%--------------------------------
%--------------------STIMFIX
stimfixEntryFcn = { 
    @()prepareStrobe(io,10); ...
	@()doStrobe(me,true); ...
	@()doSyncTime(me); ...
};  

%--------------------what to run when we are showing stimuli
stimfixFcn =  { 
	@()draw(me.stimuli); ...
	@()finishDrawing(s); ...
};

%--------------------test we maintaining fixation
testFixFcn = { 
	@()testSearchHoldFixation(eL,'stimonly','incorrect'); 
};

%--------------------as we exit stim presentation state
stimfixExitFcn = { 
	%@()sendStrobe(io,255); 
};

%--------------------------------
%--------------------STIMONLY
stim2EntryFcn = {
    @()timedTTL(rM,tS.rewardPin,tS.rewardTime); ... % labjack sends a TTL to Crist reward system
	@()changeSet(me.stimuli,3); ...
	@()edfMessage(eL,'END_FIX'); ...
};  

%--------------------what to run when we are showing stimuli
stim2Fcn =  { 
	@()draw(me.stimuli); ...
	@()finishDrawing(s); ...
};

%--------------------as we exit stim presentation state
stim2ExitFcn = { 
	%@()sendStrobe(io,255); 
};

%--------------------------------
%--------------------POST
postEntryFcn = { 
	@()edfMessage(eL,'END_RT'); ...
	@()hide(me.stimuli); ...
	@()logRun(me,'POST'); ... %fprintf current trial info
};

%--------------------correct stimulus
postFcn = { 
	
};

%--------------------when we exit the correct state
postExitFcn = { 
	%@()correct(io); ...
	@()needEyeSample(me,false); ...
	@()trackerClearScreen(eL); ...
	@()statusMessage(eL,'Ending post...'); ... %status text on the eyelink
	@()edfMessage(eL,'TRIAL_RESULT 1'); ...
	@()edfMessage(eL,'TRIAL OK'); ...
	@()stopRecording(eL); ...stimfix
	@()updateVariables(me,[],[],true); ... %randomise our stimuli, set strobe value too
	@()update(me.stimuli); ... %update our stimuli ready for display
	@()updatePlot(bR, eL, sM); ... %update our behavioural plot
	@()checkTaskEnded(me); ... %check if task is finished
};

%--------------------------------
%--------------------INCORRECT
incEntryFcn = { 
	@()edfMessage(eL,'END_RT'); ... %send END_RT to eyelink
	@()trackerClearScreen(eL); ...
	@()trackerDrawText(eL,'Incorrect! :-(');
	@()hide(me.stimuli); ... %hide fixation spot
	@()logRun(me,'INCORRECT'); ... %fprintf current trial info
}; 

%--------------------
incFcn = { 

};

%--------------------incorrect / break exit
incExitFcn = { 
	%@()incorrect(io); ...
	@()needEyeSample(me,false); ...
	@()edfMessage(eL,'TRIAL_RESULT 0'); ... %trial incorrect message
	@()stopRecording(eL); ... %stop eyelink recording data
	@()setOffline(eL); ... %set eyelink offline
	@()resetRun(t);... %we randomise the run within this block to make it harder to guess next trial
	@()updateVariables(me,[],true,false); ... %update the variables
	@()update(me.stimuli); ... %update our stimuli ready for display
	@()updatePlot(bR, eL, sM); ... %update our behavioural plot;
	@()checkTaskEnded(me); ... %check if task is finished
};

%--------------------calibration function
calibrateFcn = { 
	@()drawBackground(s); ... %blank the display
	@()setOffline(eL); ...
    %@()rstop(io); ...
    @()trackerSetup(eL) 
}; %enter tracker calibrate/validate setup mode

%--------------------debug override
overrideFcn = { @()keyOverride(me); }; %a special mode which enters a matlab debug state so we can manually edit object values

%--------------------screenflash
flashFcn = { 
	@()drawBackground(s); ...
	@()flashScreen(s, 0.2); % fullscreen flash mode for visual background activity detection
};

%show 1deg size grid
gridFcn = { @()drawGrid(s); @()drawScreenCenter(s) };

% N x 2 cell array of regexpi strings, list to skip the current -> next state's exit functions; for example
% skipExitStates = {'fixate',{'incorrect','breakfix'}}; means that if the currentstate is
% 'fixate' and the next state is either incorrect OR breakfix, then skip the FIXATE exit
% state. Add multiple rows for skipping multiple state's exit states.
sM.skipExitStates = {'fixate',{'incorrect','breakfix'}};


%==================================================================
%----------------------State Machine Table-------------------------
disp('================>> Building state info file <<================')
%specify our cell array that is read by the stateMachine
stateInfoTmp = { ...
'name'      'next'		'time'  'entryFcn'		'withinFcn'	'transitionFcn'	'exitFcn'; ...
'pause'		'prefix'	inf     pauseEntryFcn	{}			{}				pauseExitFcn; ...
'prefix'	'fixate'	1		prefixEntryFcn	prefixFcn	{}				prefixExitFcn; ...
'fixate'	'incorrect'	2		fixEntryFcn		fixFcn		initFixFcn      fixExitFcn; ...
'stimfix'	'incorrect'	2		stimfixEntryFcn stimfixFcn  testFixFcn      stimfixExitFcn; ...
'stimonly'  'post'		0.5     stim2EntryFcn	stim2Fcn	{}				stim2ExitFcn; ...
'post'		'prefix'	1		postEntryFcn	postFcn		{}				postExitFcn; ...
'incorrect'	'prefix'	1.25	incEntryFcn		incFcn		{}				incExitFcn; ...
'calibrate' 'pause'		0.5     calibrateFcn    {}			{}				{}; ...
'override'	'pause'		0.5     overrideFcn     {}			{}				{}; ...
'flash'		'pause'		0.5     flashFcn        {}			{}				{}; ...
'showgrid'	'pause'		10		{}				gridFcn		{}				{}; ...
};
%----------------------State Machine Table-------------------------
%==================================================================


disp(stateInfoTmp)
disp('================>> Loaded state info file  <<================')
clear pauseEntryFcn fixEntryFcn fixFcn initFixFcn fixExitFcn stimFcn maintainFixFcn incEntryFcn ...
	incFcn incExitFcn breakEntryFcn breakFcn correctEntryFcn correctFcn correctExitFcn ...
	calibrateFcn overrideFcn flashFcn gridFcn stimfixEntryFcn stimfixFcn testFixFcn stimfixExitFcn ...
	postEntryFcn postFcn postExitFcn prefixEntryFcn	prefixFcn
