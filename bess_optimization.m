%% Battery Energy Storage Optimization with PV and Dynamic Electricity Prices
% Requires MATLAB Optimization Toolbox (linprog).
% All powers are in kW; energy in kWh; prices in EUR/kWh.
clear; clc; close all;

T = 24; dt = 1; hours = (0:T-1)';
% Synthetic illustrative 24-hour profiles (not measured or forecast data)
load_kW = 32 + 8*exp(-((hours-8)/3).^2) + 14*exp(-((hours-18)/3).^2);
pv_kW = 30*max(0, sin(pi*(hours-6)/12));
buyPrice = 0.20 + 0.12*((hours>=7 & hours<=10) | (hours>=17 & hours<=21));
sellPrice = 0.08*ones(T,1);

capacity = 80; maxCharge = 25; maxDischarge = 25;
etaCharge = 0.95; etaDischarge = 0.95;
initialEnergy = 40; terminalEnergy = initialEnergy;

% x = [gridBuy(1:T); gridSell(1:T); charge(1:T); discharge(1:T); E(1:T+1)]
iBuy = 1:T; iSell = T+(1:T); iCharge = 2*T+(1:T);
iDischarge = 3*T+(1:T); iEnergy = 4*T+(1:T+1);
n = 5*T+1;
f = zeros(n,1); f(iBuy) = buyPrice*dt; f(iSell) = -sellPrice*dt;
lb = zeros(n,1); ub = inf(n,1);
ub(iCharge) = maxCharge; ub(iDischarge) = maxDischarge;
ub(iEnergy) = capacity;

Aeq = zeros(2*T+2,n); beq = zeros(2*T+2,1);
for t = 1:T
    % gridBuy - gridSell - charge + discharge = load - PV
    Aeq(t,iBuy(t)) = 1; Aeq(t,iSell(t)) = -1;
    Aeq(t,iCharge(t)) = -1; Aeq(t,iDischarge(t)) = 1;
    beq(t) = load_kW(t)-pv_kW(t);
    % E(t+1) - E(t) - etaCharge*charge*dt + discharge*dt/etaDischarge = 0
    r = T+t;
    Aeq(r,iEnergy(t+1)) = 1; Aeq(r,iEnergy(t)) = -1;
    Aeq(r,iCharge(t)) = -etaCharge*dt;
    Aeq(r,iDischarge(t)) = dt/etaDischarge;
end
Aeq(2*T+1,iEnergy(1)) = 1; beq(2*T+1) = initialEnergy;
Aeq(2*T+2,iEnergy(end)) = 1; beq(2*T+2) = terminalEnergy;

options = optimoptions('linprog','Display','none');
[x,optimizedCost,exitflag] = linprog(f,[],[],Aeq,beq,lb,ub,options);
if exitflag <= 0
    error('Optimization did not converge. linprog exitflag: %d',exitflag);
end

gridBuy = x(iBuy); gridSell = x(iSell);
charge = x(iCharge); discharge = x(iDischarge);
energy = x(iEnergy);
% No-storage baseline: directly import deficits and export surplus.
netLoad = load_kW-pv_kW;
baselineCost = sum(buyPrice.*max(netLoad,0) - sellPrice.*max(-netLoad,0))*dt;

fprintf('Baseline electricity cost: EUR %.2f\n',baselineCost);
fprintf('Optimized electricity cost: EUR %.2f\n',optimizedCost);
fprintf('Cost reduction: EUR %.2f (%.1f%%)\n',baselineCost-optimizedCost,100*(baselineCost-optimizedCost)/baselineCost);

figure('Color','w','Position',[100 100 1000 750]);
subplot(3,1,1);
plot(hours,load_kW,'LineWidth',1.7); hold on;
plot(hours,pv_kW,'LineWidth',1.7);
ylabel('Power (kW)'); legend('Demand','PV','Location','best'); grid on;
title('24-hour Energy System Optimization');
subplot(3,1,2);
bar(hours,[charge,-discharge],'grouped'); hold on;
plot(hours,energy(1:end-1),'k-','LineWidth',1.5);
ylabel('kW / kWh'); legend('Charge (kW)','Discharge (-kW)','Stored energy (kWh)','Location','best'); grid on;
subplot(3,1,3);
yyaxis left; plot(hours,buyPrice,'LineWidth',1.7); ylabel('Buy price (EUR/kWh)');
yyaxis right; stairs(hours,gridBuy-gridSell,'LineWidth',1.7); ylabel('Net grid import (kW)');
xlabel('Hour of day'); grid on;

% Note: With sellPrice < buyPrice and round-trip efficiency < 1, simultaneous
% import/export or charge/discharge cannot improve this objective. Therefore
% binary exclusivity constraints are unnecessary for this simplified model.
