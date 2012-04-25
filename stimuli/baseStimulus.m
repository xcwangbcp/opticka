% ========================================================================
%> @brief baseStimulus is the superclass for all opticka stimulus objects
%>
%> Superclass providing basic structure for all stimulus classes. This is a dynamic properties
%> descendant, allowing for the temporary run variables used, which get appended "name"Out, i.e.
%> speed is duplicated to a dymanic property called speedOut; it is the dynamic propertiy which is
%> used during runtime, and whose values are converted from definition units like degrees to pixel
%> values that PTB uses.
%>
% ========================================================================
classdef baseStimulus < dynamicprops
	
	properties
		%> X Position in degrees relative to screen center
		xPosition = 0
		%> Y Position in degrees relative to screen center
		yPosition = 0
		%> Size in degrees
		size = 2
		%> Colour as a 0-1 range RGBA
		colour = [0.5 0.5 0.5]
		%> Alpha as a 0-1 range
		alpha = 1
		%> Do we print details to the commandline?
		verbose=false
		%> For moving stimuli do we start "before" our initial position?
		startPosition=0
		%> speed in degs/s
		speed = 0
		%> angle in degrees
		angle = 0
	end
	
	properties (SetAccess = protected, GetAccess = public)
		%> Our screen rectangle position in PTB format
		dstRect
		%> Our screen rectangle position in PTB format
		mvRect
		%> Our texture pointer for texture-based stimuli
		texture
		%> true or false, whether to draw() this object
		isVisible = true
		%> datestamp to initialise on setup
		dateStamp
		%> tick updates on each draw, resets on each update
		tick = 1
	end
	
	properties (Dependent = true, SetAccess = private, GetAccess = public)
		%> What our per-frame motion delta is
		delta
		%> X update which is computed from our speed and angle
		dX
		%> X update which is computed from our speed and angle
		dY
	end
	
	properties (SetAccess = protected, GetAccess = protected)
		delta_
		dX_
		dY_
		%> pixels per degree (calculated in runExperiment)
		ppd = 44
		%> Inter frame interval (calculated in runExperiment)
		ifi = 0.0167
		%> computed X center (calculated in runExperiment)
		xCenter = []
		%> computed Y center (calculated in runExperiment)
		yCenter = []
		%> background colour (calculated in runExperiment)
		backgroundColour = [0.5 0.5 0.5 0]
		%> window to attach to
		win = []
		%>screen to use
		screen = []
		%> Which properties to ignore to clone when making transient copies in
		%> the setup method
		ignorePropertiesBase='family|type|dX|dY|delta|verbose|texture|dstRect|mvRect|isVisible|dateStamp|tick';
	end
	
	properties (SetAccess = private, GetAccess = private)
		allowedProperties='xPosition|yPosition|size|colour|verbose|alpha|startPosition|angle|speed'
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
		%> @return instance of class.
		% ===================================================================
		function obj = baseStimulus(varargin)
			
			if nargin>0
				obj.parseArgs(varargin, obj.allowedProperties);
			end
			
		end
		
		% ===================================================================
		%> @brief colour Get method
		%>
		% ===================================================================
		function value = get.colour(obj)
			if length(obj.colour) == 1
				value = [obj.colour obj.colour obj.colour];
			elseif length(obj.colour) == 3
				value = [obj.colour obj.alpha];
			else
				value = [obj.colour];
			end
		end
		
		% ===================================================================
		%> @brief delta Get method
		%>
		% ===================================================================
		function value = get.delta(obj)
			if isempty(obj.findprop('speedOut'));
				value = (obj.speed * obj.ppd) * obj.ifi;
			else
				value = (obj.speedOut * obj.ppd) * obj.ifi;
			end
		end
		
		% ===================================================================
		%> @brief dX Get method
		%>
		% ===================================================================
		function value = get.dX(obj)
			switch obj.family
				case 'grating'
					if isempty(obj.findprop('motionAngleOut'));
						[value,~]=obj.updatePosition(obj.delta,obj.motionAngle);
					else
						[value,~]=obj.updatePosition(obj.delta,obj.motionAngleOut);
					end
				otherwise
					if isempty(obj.findprop('angleOut'));
						[value,~]=obj.updatePosition(obj.delta,obj.angle);
					else
						[value,~]=obj.updatePosition(obj.delta,obj.angleOut);
					end
			end
		end
		
		% ===================================================================
		%> @brief dY Get method
		%>
		% ===================================================================
		function value = get.dY(obj)
			switch obj.family
				case 'grating'
					if isempty(obj.findprop('motionAngleOut'));
						[~,value]=obj.updatePosition(obj.delta,obj.motionAngle);
					else
						[~,value]=obj.updatePosition(obj.delta,obj.motionAngleOut);
					end
				otherwise
					if isempty(obj.findprop('angleOut'));
						[~,value]=obj.updatePosition(obj.delta,obj.angle);
					else
						[~,value]=obj.updatePosition(obj.delta,obj.angleOut);
					end
			end
		end
		
		% ===================================================================
		%> @brief Shorthand to set isVisible=true.
		%>
		% ===================================================================
		function show(obj)
			obj.isVisible = true;
		end
		
		% ===================================================================
		%> @brief Shorthand to set isVisible=false.
		%>
		% ===================================================================
		function hide(obj)
			obj.isVisible = false;
		end
		
		% ===================================================================
		%> @brief Run Stimulus in a window to preview
		%>
		% ===================================================================
		function run(obj)
			s = screenManager('screen',0,'bitDepth','8bit','debug',true); %use a temporary screenManager object
			s.windowed = CenterRect([0 0 s.screenVals.width/2 s.screenVals.height/2], s.winRect); %middle of screen
			s.open(); %open PTB screen
			obj.setup(s); %setup our stimulus object
			obj.draw(); %draw stimulus
			s.drawGrid(); %draw +-5 degree dot grid
			s.drawFixationPoint(); %centre spot
			Screen('Flip',s.win);
			WaitSecs(1);
			for i = 1:(s.screenVals.fps*2) %should be 2 seconds worth of flips
				obj.draw(); %draw stimulus
				s.drawGrid(); %draw +-5 degree dot grid
				s.drawFixationPoint(); %centre spot
				Screen('DrawingFinished', s.win); %tell PTB to draw
				obj.animate(); %animate stimulus, will be seen on next draw
				Screen('Flip',s.win); %flip the buffer ASAP, timing is unimportant
			end
			WaitSecs(1);
			s.drawGrid(); %draw +-5 degree dot grid
			Screen('Flip',s.win);
			WaitSecs(0.25);
			s.close(); %close screen
			clear s; %clear it
			obj.reset(); %reset our stimulus ready for use again
		end
		
		
	end %---END PUBLIC METHODS---%
	
	%=======================================================================
	methods (Abstract)%------------------ABSTRACT METHODS
	%=======================================================================
		%> initialise the stimulus
		out = setup(runObject)
		%> update the stimulus
		out = update(runObject)
		%>draw to the screen buffer
		out = draw(runObject)
		%> animate the settings
		out = animate(runObject)
		%> reset to default values
		out = reset(runObject)
	end %---END ABSTRACT METHODS---%
	
	%=======================================================================
	methods ( Static ) %----------STATIC METHODS
	%=======================================================================
		
		% ===================================================================
		%> @brief degrees2radians
		%>
		% ===================================================================
		function r = d2r(degrees)
			r=degrees*(pi/180);
		end
		
		% ===================================================================
		%> @brief radians2degrees
		%>
		% ===================================================================
		function degrees=r2d(r)
			degrees=r*(180/pi);
		end
		
		% ===================================================================
		%> @brief findDistance in X and Y coordinates
		%>
		% ===================================================================
		function distance=findDistance(x1,y1,x2,y2)
			dx = x2 - x1;
			dy = y2 - y1;
			distance=sqrt(dx^2 + dy^2);
		end
		
		% ===================================================================
		%> @brief updatePosition returns dX and dY given an angle and delta
		%>
		% ===================================================================
		function [dX dY] = updatePosition(delta,angle)
			dX = delta .* cos(baseStimulus.d2r(angle));
			dY = delta .* sin(baseStimulus.d2r(angle));
			%if abs(dX) < 1e-6; dX = 0; end
			%if abs(dY) < 1e-6; dY = 0; end
		end
		
	end%---END STATIC METHODS---%
	
	%=======================================================================
	methods ( Access = protected ) %-------PRIVATE (protected) METHODS-----%
	%=======================================================================
		
		
		% ===================================================================
		%> @brief setRect
		%>  setRect makes the PsychRect based on the texture and screen values
		% ===================================================================
		function setRect(obj)
			if isempty(obj.findprop('angleOut'));
				[dx dy]=pol2cart(obj.d2r(obj.angle),obj.startPosition);
			else
				[dx dy]=pol2cart(obj.d2r(obj.angleOut),obj.startPosition);
			end
			obj.dstRect=Screen('Rect',obj.texture);
			obj.dstRect=CenterRectOnPointd(obj.dstRect,obj.xCenter,obj.yCenter);
			if isempty(obj.findprop('xPositionOut'));
				obj.dstRect=OffsetRect(obj.dstRect,obj.xPosition*obj.ppd,obj.yPosition*obj.ppd);
			else
				obj.dstRect=OffsetRect(obj.dstRect,obj.xPositionOut+(dx*obj.ppd),obj.yPositionOut+(dy*obj.ppd));
			end
			obj.mvRect=obj.dstRect;
			obj.setAnimationDelta();
		end
		
		% ===================================================================
		%> @brief setAnimationDelta
		%> setAnimationDelta for performance we can't use get methods for dX dY and
		%> delta during animation, so we have to cache these properties to private copies so that
		%> when we call the animate method, it uses the cached versions not the
		%> public versions. This method simply copies the properties to their cached
		%> equivalents.
		% ===================================================================
		function setAnimationDelta(obj)
			obj.delta_ = obj.delta;
			obj.dX_ = obj.dX;
			obj.dY_ = obj.dY;
		end
		
		% ===================================================================
		%> @brief compute xTmp and yTmp
		%>
		% ===================================================================
		function computePosition(obj)
			if isempty(obj.findprop('angleOut'));
				[dx dy]=pol2cart(obj.d2r(obj.angle),obj.startPosition);
			else
				[dx dy]=pol2cart(obj.d2r(obj.angleOut),obj.startPositionOut);
			end
			obj.xTmp = obj.xPositionOut + (dx * obj.ppd);
			obj.yTmp = obj.yPositionOut + (dy * obj.ppd);
		end
		
		% ===================================================================
		%> @brief Converts properties to a structure
		%>
		%>
		%> @param obj this instance object
		%> @param tmp is whether to use the temporary or permanent properties
		%> @return out the structure
		% ===================================================================
		function out=toStructure(obj,tmp)
			if ~exist('tmp','var')
				tmp = 0; %copy real properties, not temporary ones
			end
			fn = fieldnames(obj);
			for j=1:length(fn)
				if tmp == 0
					out.(fn{j}) = obj.(fn{j});
				else
					out.(fn{j}) = obj.([fn{j} 'Out']);
				end
			end
		end
		
		% ===================================================================
		%> @brief Finds and removes transient properties
		%>
		%> @param obj
		%> @return
		% ===================================================================
		function removeTmpProperties(obj)
			fn=fieldnames(obj);
			for i=1:length(fn)
				if ~isempty(regexp(fn{i},'Out$','once'))
					delete(obj.findprop(fn{i}));
				end
			end
		end
		
		% ===================================================================
		%> @brief Sets properties from a structure or normal arguments,
		%> ignores invalid properties
		%>
		%> @param args input structure
		%> @param allowedProperties properties possible to set on construction
		% ===================================================================
		function parseArgs(obj, args, allowedProperties)
			allowedProperties = ['^(' allowedProperties ')$'];
			
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
			
			if isstruct(args)
				fnames = fieldnames(args); %find our argument names
				for i=1:length(fnames);
					if regexp(fnames{i},allowedProperties) %only set if allowed property
						obj.salutation(fnames{i},'Configuring setting in constructor');
						obj.(fnames{i})=args.(fnames{i}); %we set up the properies from the arguments as a structure
					end
				end
			end
			
		end
		
		% ===================================================================
		%> @brief Prints messages dependent on verbosity
		%>
		%> Prints messages dependent on verbosity
		%> @param obj this instance object
		%> @param in the calling function
		%> @param message the message that needs printing to command window
		% ===================================================================
		function salutation(obj,in,message)
			if obj.verbose==true
				if ~exist('in','var')
					in = 'undefined';
				end
				if exist('message','var')
					fprintf(['---> ' obj.family ': ' message ' | ' in '\n']);
				else
					fprintf(['---> ' obj.family ': ' in '\n']);
				end
			end
		end
	end%---END PRIVATE METHODS---%
end