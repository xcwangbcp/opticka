classdef timeLogger < optickaCore
	%TIMELOG Simple class used to store the timing data from an experiment
	%   timeLogger stores timing data for a taskrun and optionally graphs the
	%   result.
	
	properties
		screenLog	= struct()
		timer		= @GetSecs
		vbl			= 0
		show		= 0
		flip		= 0
		miss		= 0
		stimTime	= 0
		tick		= 0
		tickInfo	= 0
		startTime	= 0
		startRun	= 0
		verbose		= true
	end
	
	properties (SetAccess = private, GetAccess = public)
		missImportant
		nMissed
	end
	
	properties (SetAccess = private, GetAccess = private)
		runLog		= struct()
		trainingLog	= struct()
		%> allowed properties passed to object upon construction
		allowedProperties = 'timer'
	end
	
	%=======================================================================
	methods %------------------PUBLIC METHODS
	%=======================================================================

		% ===================================================================
		%> @brief Constructor
		%>
		%> @param varargin
		%> @return
		% ===================================================================
		function obj=timeLogger(varargin)
			if nargin == 0; varargin.name = 'timeLog';end
			if nargin>0; obj.parseArgs(varargin,obj.allowedProperties); end
			if isempty(obj.name);obj.name = 'timeLog'; end
			if ~exist('GetSecs','file')
				obj.timer = @now;
			end
			obj.screenLog.construct = obj.timer();
		end
		
		% ===================================================================
		%> @brief Preallocate array a bit more efficient
		%>
		%> @param varargin
		%> @return
		% ===================================================================
		function preAllocate(obj,n)
			obj.vbl = zeros(1,n);
			obj.show = obj.vbl;
			obj.flip = obj.vbl;
			obj.miss = obj.vbl;
			obj.stimTime = obj.vbl;
		end
		
		% ===================================================================
		%> @brief if we preallocated, remove empty 0 values
		%>
		%> @param
		%> @return
		% ===================================================================
		function removeEmptyValues(obj)
			idx = find(obj.vbl == 0);
			obj.vbl(idx) = [];
			obj.show(idx) = [];
			obj.flip(idx) = [];
			obj.miss(idx) = [];
			obj.stimTime(idx) = [];
			index=min([length(obj.vbl) length(obj.flip) length(obj.show)]);
			obj.vbl=obj.vbl(1:index);
			obj.show=obj.show(1:index);
			obj.flip=obj.flip(1:index);
			obj.miss=obj.miss(1:index);
			obj.stimTime=obj.stimTime(1:index);
		end
		
		% ===================================================================
		%> @brief print Log of the frame timings
		% ===================================================================
		function plot(obj)
			obj.printRunLog();
		end
		
		% ===================================================================
		%> @brief print Log of the frame timings
		%>
		%> @param
		%> @return
		% ===================================================================
		function printRunLog(obj)
			if length(obj.vbl) <= 5
				disp('No timing data available...')
				return
			end
			
			removeEmptyValues(obj)
			
			vbl=obj.vbl.*1000; %#ok<*PROP>
			show=obj.show.*1000;
			flip=obj.flip.*1000; 
			miss=obj.miss;
			stimTime=obj.stimTime;
			
			calculateMisses(obj,miss,stimTime)
			
			figure;
			set(gcf,'Name',obj.name,'NumberTitle','off','Color',[1 1 1]);
			p = panel('defer');
			p.pack(3,1)
			
			p(1,1).select();
			hold on
			vv=diff(vbl);
			vv(vv>100)=100;
			plot(vv,'ro:')
			ss=diff(show);
			ss(ss>100)=100;
			plot(ss,'b--')
			ff = diff(flip);
			ff(ff>100)=100;
			plot(ff,'g-.')
			plot(stimTime(2:end)*100,'k-')
			hold off
			legend('VBL','Show','Flip','Stim ON')
			[m,e]=obj.stderr(diff(vbl));
			t=sprintf('VBL mean=%2.2f+-%2.2f s.e.', m, e);
			[m,e]=obj.stderr(diff(show));
			t=[t sprintf(' | Show mean=%2.2f+-%2.2f', m, e)];
			[m,e]=obj.stderr(diff(flip));
			t=[t sprintf(' | Flip mean=%2.2f+-%2.2f', m, e)];
			p(1,1).title(t)
			p(1,1).xlabel('Frame number (difference between frames)');
			p(1,1).ylabel('Time (milliseconds)');
			
			
			p(2,1).select();
			x = 1:length(show);
			hold on
			plot(x,show-vbl,'r')
			plot(x,show-flip,'g')
			plot(x,vbl-flip,'b-.')
			plot(x,stimTime-0.5,'k')
			legend('Show-VBL','Show-Flip','VBL-Flip','Simulus ON/OFF');
			hold off
% 			ax1=gca;
% 			ax2 = axes('Position',get(ax1,'Position'),...
% 				'XAxisLocation','top',...
% 				'YAxisLocation','right',...
% 				'Color','none',...
% 				'XColor','k','YColor','k');
% 			hl2 = line(x,stimTime,'Color','k','Parent',ax2);
% 			set(ax2,'YLim',[-1 2])
% 			set(ax2,'YTick',[-1 0 1 2])
% 			set(ax2,'YTickLabel',{'','BLANK','STIMULUS',''})
% 			linkprop([ax1 ax2],'Position');
			[m,e]=obj.stderr(show-vbl);
			t=sprintf('Show-VBL=%2.2f+-%2.2f', m, e);
			[m,e]=obj.stderr(show-flip);
			t=[t sprintf(' | Show-Flip=%2.2f+-%2.2f', m, e)];
			[m,e]=obj.stderr(vbl-flip);
			t=[t sprintf(' | VBL-Flip=%2.2f+-%2.2f', m, e)];
			p(2,1).title(t);
			p(2,1).xlabel('Frame number');
			p(2,1).ylabel('Time (milliseconds)');
			
			p(3,1).select();
			hold on
			miss(miss > 0.05) = 0.05;
			plot(miss,'k.-');
			plot(obj.missImportant,'ro','MarkerFaceColor',[1 0 0]);
			plot(stimTime/30,'k','linewidth',1);
			hold off
			p(3,1).title(['Missed frames = ' num2str(obj.nMissed) ' (RED > 0 means missed frame)']);
			p(3,1).xlabel('Frame number');
			p(3,1).ylabel('Miss Value');
			
			scnsize = get(0,'ScreenSize');
			set(gcf,'Position', [10 1 round(scnsize(3)/3) scnsize(4)]);
			p.refresh();
			clear vbl show flip index miss stimTime
		end
		
		% ===================================================================
		%> @brief calculate genuine missed stim frames
		%>
		%> @param
		%> @return
		% ===================================================================
		function calculateMisses(obj,miss,stimTime)
			removeEmptyValues(obj)
			if nargin == 1
				miss = obj.miss;
				stimTime = obj.stimTime;
			end
			obj.missImportant = miss;
			obj.missImportant(obj.missImportant <= 0) = -inf;
			obj.missImportant(stimTime < 1) = -inf;
			obj.missImportant(1) = -inf; %ignore first frame
			obj.nMissed = length(find(obj.missImportant > 0));
		end
	end %---END PUBLIC METHODS---%
	
	%=======================================================================
	methods ( Access = private ) %-------PRIVATE METHODS-----%
	%=======================================================================
		
		% ===================================================================
		%> @brief 
		%>
		%> @param
		%> @return
		% ===================================================================
		function [avg,err] = stderr(obj,data)
			avg=mean(data);
			err=std(data);
			err=sqrt(err.^2/length(data));
		end
		
	end
	
end

