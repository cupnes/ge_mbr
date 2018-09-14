#!/bin/bash

# set -eux

# POPULATION_SIZEは、
# - 2で2回割っても余りが出ない
# - 5で1回割っても余りが出ない
# を共に満たす値であること
# すなわち、20の倍数
POPULATION_SIZE=20
GENE_LEN=510
MBR_TESTER=./mbr_tester
WORK_DIR=$(date '+%Y%m%d%H%M%S')

generate() {
	local i

	file=$1
	ch_len=${GENE_LEN}
	for i in $(seq ${ch_len}); do
		rnd=$((RANDOM % 256))
		echo -en "\x$(printf '%02x' $rnd)" >> $file
	done
	echo -en '\x55\xaa' >> $file
}

initialization() {
	local i

	echo 'initialization'
	echo '-------------------------------------------'

	mkdir ${WORK_DIR}
	echo "WORK_DIR=${WORK_DIR}"
	mkdir ${WORK_DIR}/{now,next}
	for i in $(seq 0 $((POPULATION_SIZE - 1))); do
		echo "${WORK_DIR}/now/ch_$i.dat"
		generate "${WORK_DIR}/now/ch_$i.dat"
	done

	echo
	echo
}

evaluation() {
	local i
	local tmp

	echo 'evaluation'
	echo '-------------------------------------------'

	rm -f tmp.csv

	for i in $(seq 0 $((POPULATION_SIZE - 1))); do
		echo "i=$i"
		ch=${WORK_DIR}/now/ch_$i.dat
		echo ">>>>> $ch"

		cp $ch floppy.img
		$MBR_TESTER
		exit_code=$?
		case $exit_code in
		0)
			evaluation_value=100
			echo "$ch has reached the answer!"
			rm -f enable_ge
			;;
		1)
			evaluation_value=1
			echo "$ch is an ordinary child."
			;;
		*)
			evaluation_value=0
			echo "$ch is dead."
			;;
		esac

		echo "ch_$i.dat,${evaluation_value}" >> tmp.csv
		echo "evaluation_value=${evaluation_value}"

		echo
		echo
	done

	# 第2列で降順にソート
	sort -n -r -k 2 -t ',' tmp.csv > ${WORK_DIR}/now/evaluation_value_list.csv

	echo
	echo
}

evaluation_test() {
	local i

	echo 'evaluation_test'
	echo '-------------------------------------------'

	rm -f tmp.csv

	for i in $(seq 0 $((POPULATION_SIZE - 1))); do
		echo "ch_$i.dat,$(((RANDOM % 100) + 1))" >> tmp.csv
	done

	# 第2列で降順にソート
	sort -n -r -k 2 -t ',' tmp.csv > ${WORK_DIR}/now/evaluation_value_list.csv

	echo
	echo
}

two_point_crossover() {
	chA=$1
	chB=$2
	child1=$3
	child2=$4

	echo '>>>>>>>>>>>> Two-point crossover'
	echo "chA=$chA"
	echo "chB=$chB"
	echo "child1=$child1"
	echo "child2=$child2"

	p1=0
	while [ $p1 -le 2 ]; do
		p1=$(((RANDOM % GENE_LEN) + 1))
	done
	echo "p1=$p1"
	p2=0
	while [ $p2 -le 1 ]; do
		p2=$(((RANDOM % (p1 - 1)) + 1))
	done
	echo "p2=$p2"

	sed -n "1,$((p2 - 1))p" $chA > tmp_chAt.dat
	sed -n "1,$((p2 - 1))p" $chB > tmp_chBt.dat
	sed -n "$p2,$((p1 - 1))p" $chA > tmp_chAm.dat
	sed -n "$p2,$((p1 - 1))p" $chB > tmp_chBm.dat
	sed -n "$p1,\$p" $chA > tmp_chAb.dat
	sed -n "$p1,\$p" $chB > tmp_chBb.dat

	cat tmp_chAt.dat tmp_chBm.dat tmp_chAb.dat > $child1
	cat tmp_chBt.dat tmp_chAm.dat tmp_chBb.dat > $child2

	rm -f tmp_chAt.dat tmp_chBm.dat tmp_chAb.dat
	rm -f tmp_chBt.dat tmp_chAm.dat tmp_chBb.dat
}

uniform_crossover() {
	local ch_idx
	local chA_byte
	local chB_byte
	chA=$1
	chB=$2
	child1=$3
	child2=$4

	echo '>>>>>>>>>>>> Uniform crossover'
	echo "chA=$chA"
	echo "chB=$chB"
	echo "child1=$child1"
	echo "child2=$child2"

	rm -f $child1 $child2

	# echo -n 'Crossover idx:'
	for ch_idx in $(seq ${GENE_LEN}); do
		chA_byte=$(xxd -g1 -c1 -p $chA | sed -n "${ch_idx}p")
		chB_byte=$(xxd -g1 -c1 -p $chB | sed -n "${ch_idx}p")
		if [ $((RANDOM % 2)) -lt 1 ]; then
			# echo -n "${ch_idx} "
			echo -en "\x${chA_byte}" >> $child2
			echo -en "\x${chB_byte}" >> $child1
		else
			echo -en "\x${chA_byte}" >> $child1
			echo -en "\x${chB_byte}" >> $child2
		fi
	done
	echo -en '\x55\xaa' >> $child1
	echo -en '\x55\xaa' >> $child2
	echo
}

partial_crossover() {
	local cross_idx
	local chA_byte
	local chB_byte
	chA=$1
	chB=$2
	child1=$3
	child2=$4

	cross_idx=$(((RANDOM % GENE_LEN) + 1))

	echo '>>>>>>>>>>>> Partial crossover'
	echo "chA=$chA"
	echo "chB=$chB"
	echo "child1=$child1"
	echo "child2=$child2"
	echo "cross_idx=$cross_idx"

	rm -f $child1 $child2

	for ch_idx in $(seq ${GENE_LEN}); do
		chA_byte=$(xxd -g1 -c1 -p $chA | sed -n "${ch_idx}p")
		chB_byte=$(xxd -g1 -c1 -p $chB | sed -n "${ch_idx}p")
		if [ $ch_idx -eq $cross_idx ]; then
			echo -en "\x${chA_byte}" >> $child2
			echo -en "\x${chB_byte}" >> $child1
		else
			echo -en "\x${chA_byte}" >> $child1
			echo -en "\x${chB_byte}" >> $child2
		fi
	done
	echo -en '\x55\xaa' >> $child1
	echo -en '\x55\xaa' >> $child2
	echo
}

selection() {
	local i

	echo 'selection'
	echo '-------------------------------------------'

	candidates_num=$((POPULATION_SIZE / 2))
	mutation_num=$((POPULATION_SIZE / 5))
	top_num=$((POPULATION_SIZE - (candidates_num + mutation_num)))

	# 淘汰
	# evaluation_value=0の個体を一番良い個体で置き換える
	echo ">>>>>>> To be culled"
	top_ch=$(awk -F',' '{print $1;exit}' ${WORK_DIR}/now/evaluation_value_list.csv)
	echo "top_ch:${WORK_DIR}/now/${top_ch}"
	for i in $(awk -F',' '$2==0{print $1}' ${WORK_DIR}/now/evaluation_value_list.csv); do
		mkdir -p ${WORK_DIR}/${age}_culled
		mv ${WORK_DIR}/now/${i} ${WORK_DIR}/${age}_culled/
		echo "save $i to ${WORK_DIR}/${age}_culled/"
		cp ${WORK_DIR}/now/${top_ch} ${WORK_DIR}/now/$i
		echo "replace ${WORK_DIR}/now/$i with ${WORK_DIR}/now/${top_ch}"
	done

	echo

	# (個体数 - (残した子孫の数 + 突然変異数))分の個体を、上位から順にnextへコピー
	echo ">>>>>>> Copy Top ${top_num}"
	for i in $(seq ${top_num}); do
		line=$(sed -n ${i}p ${WORK_DIR}/now/evaluation_value_list.csv)
		echo "line:$line"
		cp ${WORK_DIR}/{now,next}/$(echo $line | cut -d',' -f1)
		echo "save_to_next:${WORK_DIR}/now/$(echo $line | cut -d',' -f1)"
	done

	echo

	# 上位50%の個体を候補に、同数の個体をnextへ追加
	# (一様交叉を使用)
	echo '>>>>>>> Crossover'
	max_cross_times=$((candidates_num / 2))
	for cross_times in $(seq 0 $((max_cross_times - 1))); do
		echo "cross_times=${cross_times}"

		chA_idx=$(((RANDOM % candidates_num) + 1))
		chB_idx=${chA_idx}
		while [ ${chB_idx} -eq ${chA_idx} ]; do
			chB_idx=$(((RANDOM % candidates_num) + 1))
		done
		echo "chA_idx=${chA_idx} , chB_idx=${chB_idx}"

		chA=${WORK_DIR}/now/$(sed -n ${chA_idx}p ${WORK_DIR}/now/evaluation_value_list.csv | cut -d',' -f1)
		chB=${WORK_DIR}/now/$(sed -n ${chB_idx}p ${WORK_DIR}/now/evaluation_value_list.csv | cut -d',' -f1)
		echo "chA=$chA"
		echo "chB=$chB"
		partial_crossover $chA $chB child$((2 * cross_times)).dat child$(((2 * cross_times) + 1)).dat

		echo
	done

	cross_idx=0
	for i in $(seq 0 $((POPULATION_SIZE - 1))); do
		[ ${cross_idx} -ge ${candidates_num} ] && break
		if [ ! -f ${WORK_DIR}/next/ch_$i.dat ]; then
			mv child${cross_idx}.dat ${WORK_DIR}/next/ch_$i.dat
			echo "mv child${cross_idx}.dat ${WORK_DIR}/next/ch_$i.dat"
			cross_idx=$((cross_idx + 1))
		fi
	done

	echo

	# 個体数の20%を突然変異させ、nextへ追加
	echo '>>>>>>> Mutation'
	for mutation_cnt in $(seq ${mutation_num}); do
		for i in $(seq 0 $((POPULATION_SIZE - 1))); do
			if [ ! -f ${WORK_DIR}/next/ch_$i.dat ]; then
				generate ${WORK_DIR}/next/ch_$i.dat
				echo "mutated:${WORK_DIR}/next/ch_$i.dat"
				break
			fi
		done
	done

	echo
	echo
}

if [ $# -ge 1 ]; then
	WORK_DIR=$1
	echo "Use WORK_DIR=${WORK_DIR}"
else
	echo "Initialization"
	initialization
fi

if [ $# -ge 2 ]; then
	age=$2
	echo "It will start in the generation $age."
else
	age=0
fi

touch enable_ge
while [ -f enable_ge ]; do
	echo "GE: age=$age"
	echo '-------------------------------------------'

	evaluation
	# evaluation_test
	selection
	mv ${WORK_DIR}/{now,$age}
	mv ${WORK_DIR}/{next,now}
	mkdir ${WORK_DIR}/next
	age=$((age + 1))

	echo
	echo
done

echo '-------------------------------------------'
echo "Stopped at $(date '+%Y-%m-%d %H:%M:%S')"
echo 'Continue Command'
echo "$0 ${WORK_DIR} $age"
echo '-------------------------------------------'

# # 一様交叉(Uniform Crossover)テストスクリプト
# rm -f chA.dat chB.dat
# for ch_idx in $(seq ${GENE_LEN}); do
# 	echo A >> chA.dat
# 	echo B >> chB.dat
# done
# uniform_crossover chA.dat chB.dat child1.dat child2.dat
