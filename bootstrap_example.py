# -*- coding: utf-8 -*-
"""
Created on Thu Jan 12 15:26:15 2017

Bootstrapping example in Python
Simulate the spelling of picking random letters to spell a three letter word,
then bootstrap the results to find a confidence interval.

@author: Mike Miranda
"""



import string
import random
import numpy as np
from statistics import mean


def spell(x):
    for y in range(x):
        return ''.join(random.choice(string.ascii_lowercase) for n in range(x))

summary = []        
        
for n in range(100):
    tries = 0
    while True:
        name = spell(3)
        if name != 'tre':
            tries += 1
            #print('generated:',name,'. current number of tries:',tries)
        else:
            print('step ',n+1,'. it took',tries,'to spell tre')
            summary.append(tries)
            break

#take 10000 elements with replacement from summary, split into 100 lists, and analyze        
bootstrap = []
for n in range(100000):
    bootstrap.append(summary[random.randint(0,99)])
#splitting
sims = np.array_split(bootstrap,1000)
#find means of groups of 100s
bootstrap_mean = []
for n in range(len(sims)):
    bootstrap_mean.append(mean(sims[n]))


bootstrap_mean.sort()

#90% confidence interval
min_endpoint = int(1000*.05)
max_endpoint = int(1000*.95)

#endpoints
print('90% confidence interval: [',bootstrap_mean[min_endpoint],':',bootstrap_mean[max_endpoint],']')
