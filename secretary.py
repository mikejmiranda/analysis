import numpy as np
import pandas as pd
import math

sample = 100
trials = 1000
saved_trials = pd.DataFrame()


for n in range(trials):
    df = pd.DataFrame(np.random.randint(1,100,size=(sample,1)), columns=list(['Rating']))
    df['Candidate'] = df.index+1
    df['Rank'] = df['Rating'].rank(ascending=False, method='min')
    n = round(len(df)/math.e)
    min_rating = df.loc[df['Candidate'] <= n, 'Rating'].max()
    
    #need to find the first candidate after n with a rating > min_rating
    k = n+1
    while True:
        if k == df['Candidate'].max():
            saved_trials = saved_trials.append(df.loc[k-1])
            break
        elif df['Rating'][k-1] >= min_rating:
            saved_trials = saved_trials.append(df.loc[k-1])
            break
        elif df['Rating'][k-1] < min_rating:
            k = k+1

saved_trials = saved_trials.reset_index()

          
len(saved_trials[saved_trials['Rank']==1])/len(saved_trials)
