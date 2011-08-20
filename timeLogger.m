classdef timeLogger < dynamicprops
	%TIMELOG Summary of this class goes here
	%   Detailed explanation goes here
	
	properties
		date = 0
		startRun = 0
		vbl = 0
		show = 0
		flip = 0
		miss = 0
		stimTime = 0
		construct = 0
		screen = struct
	end
	
	methods
		function obj=timeLogger
			obj.screen.construct = GetSecs;
			obj.date = clock;
		end
		
		% ===================================================================
		%> @brief print Log of the frame timings
		%>
		%> @param
		%> @return
		% ===================================================================
		function printLog(obj)
			if obj.logFrames == false || ~isfield(obj.timeLog,'date')
				disp('No timing data available')
				return
			end
			vbl=obj.vbl*1000;
			show=obj.show*1000;
			flip=obj.flip*1000;
			index=min([length(vbl) length(flip) length(show)]);
			vbl=vbl(1:index);
			show=show(1:index);
			flip=flip(1:index);
			miss=obj.miss(1:index);
			stimTime=obj.stimTime(1:index);
			
			figure;
			
			p = panel('defer');
			p.pack(3,1)
			
			scnsize = get(0,'ScreenSize');
			pos=get(gcf,'Position');
			
			p(1,1).select();
			plot(diff(vbl),'ro:')
			hold on
			plot(diff(show),'b--')
			plot(diff(flip),'g-.')
			hold off
			legend('VBL','Show','Flip')
			[m,e]=stderr(diff(vbl),'SE');
			t=sprintf('VBL mean=%2.2f+-%2.2f s.e.', m, e);
			[m,e]=stderr(diff(show),'SE');
			t=[t sprintf(' | Show mean=%2.2f+-%2.2f', m, e)];
			[m,e]=stderr(diff(flip),'SE');
			t=[t sprintf(' | Flip mean=%2.2f+-%2.2f', m, e)];
			p(1,1).title(t)
			p(1,1).xlabel('Frame number (difference between frames)');
			p(1,1).ylabel('Time (milliseconds)');
			
			
			p(2,1).select();
			hold on
			plot(show-vbl,'r')
			plot(show-flip,'g')
			plot(vbl-flip,'b')
			plot(stimTime*2,'k');
			hold off
			legend('Show-VBL','Show-Flip','VBL-Flip');
			[m,e]=stderr(show-vbl,'SE');
			t=sprintf('Show-VBL=%2.2f+-%2.2f', m, e);
			[m,e]=stderr(show-flip,'SE');
			t=[t sprintf(' | Show-Flip=%2.2f+-%2.2f', m, e)];
			[m,e]=stderr(vbl-flip,'SE');
			t=[t sprintf(' | VBL-Flip=%2.2f+-%2.2f', m, e)];
			p(2,1).title(t);
			p(2,1).xlabel('Frame number');
			p(2,1).ylabel('Time (milliseconds)');
			
			p(3,1).select();
			hold on
			plot(miss,'r.-')
			plot(stimTime/100,'k');
			hold off
			p(3,1).title('Missed frames (> 0 means missed frame)');
			p(3,1).xlabel('Frame number');
			p(3,1).ylabel('Miss Value');
			
			newpos = [pos(1) 1 pos(3) scnsize(4)];
			set(gcf,'Position',newpos);
			p.refresh();
			clear vbl show flip index miss stimTime
		end
	end
	
end

